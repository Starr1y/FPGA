"""Loopback-only authenticated API and shared serial command scheduler."""
import csv,json,math,queue,secrets,threading,time,uuid,struct,socket
from collections import deque
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import numpy as np
import lab_protocol as P
from lab_ui import spectrum
from lab_duo import execute_duo

STATES={'queued':'已排队','running':'执行中','acknowledged':'设备已应答','completed':'已完成',
        'failed':'失败','cancelled':'已取消','simulated':'模拟完成'}
COMMANDS=['connect','disconnect','demo','voices.set','voices.release','capture','preview',
          'imu.mode','imu.configure','ping','record.start','record.stop','replay','export',
          'eda.synthesis','eda.build','eda.stop','test.two_voice_spi',
          'instrument.demo','instrument.set','duo.expression','monitor.select','sine.start','sine.stop','duo.demo','duo.configure','duo.select','duo.strike','duo.stop']

class Cancelled(Exception):pass

class LocalHTTPServer(ThreadingHTTPServer):
    # Windows SO_REUSEADDR can bind two instances to the same port and send
    # a valid token to the wrong instance. Fall back to a distinct port.
    allow_reuse_address=False
    def server_bind(self):
        if hasattr(socket,'SO_EXCLUSIVEADDRUSE'):self.socket.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
        super().server_bind()

class CommandController:
    def __init__(self,engine,root,ui_call=None):
        self.engine=engine;self.root=Path(root);self.ui_call=ui_call
        self.jobs={};self.lock=threading.RLock();self.queue=queue.Queue(64)
        self.events=deque(maxlen=100);self.active=None;self.closed=threading.Event()
        self.capture_timeout_s=15
        self.aux_workers=set()
        self.worker=threading.Thread(target=self._work,daemon=True);self.worker.start()
    def submit(self,action,params=None):
        if action not in COMMANDS:raise ValueError('未知命令：'+action)
        if not isinstance(params or {},dict):raise ValueError('params 必须是 JSON 对象')
        with self.lock:
            if action=='duo.select':
                old=next((j for j in self.jobs.values() if j['action']==action and j['state']=='queued' and j['params'].get('hand')==(params or {}).get('hand')),None)
                if old:old['params']=dict(params or {});return self.job(old['id'])
            if action=='capture':
                existing=next((j for j in self.jobs.values() if j['action']=='capture' and j['state'] not in ('completed','failed','cancelled')),None)
                if existing:
                    if (existing['params'].get('trigger',0),existing['params'].get('points',2048))!=((params or {}).get('trigger',0),(params or {}).get('points',2048)):raise ValueError('已有抓取等待完成，请勿同时更换触发方式或点数；过零卡住时需复位FPGA')
                    return self.job(existing['id'])
            if len(self.jobs)>=200:
                for key,j in list(self.jobs.items()):
                    if j['state'] in ('completed','failed','cancelled'):del self.jobs[key];break
            j=dict(id=uuid.uuid4().hex,action=action,params=params or {},state='queued',message='已排队',
                   created=time.time(),cancel=threading.Event(),history=[])
            if action=='eda.stop' and self.active and self.jobs[self.active]['action'] in ('eda.build','eda.synthesis'):
                self.jobs[self.active]['cancel'].set()
            if action in ('duo.stop','sine.stop'):
                for old in self.jobs.values():
                    if (old['action'] in ('duo.strike','duo.select','duo.configure','sine.start') and old['state']=='queued') or (old['action']=='sine.start' and old['state'] not in ('completed','failed','cancelled')):old['cancel'].set()
                self.jobs[j['id']]=j;self.start_aux(j)
            else:self.queue.put_nowait(j);self.jobs[j['id']]=j
            return self.job(j['id'])
    def start_aux(self,j):
        def run():
            try:self.run_job(j)
            finally:
                with self.lock:self.aux_workers.discard(threading.current_thread())
        t=threading.Thread(target=run,daemon=True);self.aux_workers.add(t);t.start()
    def run_job(self,j):
        try:
            if j['cancel'].is_set():raise Cancelled('排队操作已取消')
            self.update(j,'running','执行中')
            result=self.execute(j,j['action'],j['params'])
            self.update(j,'cancelled' if j['cancel'].is_set() else 'completed',
                        '已取消，清理结果见任务输出' if j['cancel'].is_set() else ('数据已完成' if j['action'] in ('capture','replay','export') else '操作完成'),result=result)
        except Cancelled as exc:self.update(j,'cancelled',str(exc))
        except Exception as exc:self.update(j,'failed',str(exc))
    def job(self,key):
        with self.lock:
            j=self.jobs[key]
            return {k:v for k,v in j.items() if k not in ('cancel','params')}
    def update(self,j,state,message,**extra):
        with self.lock:
            j.update(state=state,message=message,**extra)
            j['history'].append(dict(time=time.time(),state=state,message=message))
            j['history']=j['history'][-40:]
            self.events.append(f"{time.strftime('%H:%M:%S')} {j['action']}：{message}")
    def cancel(self,key):
        with self.lock:self.jobs[key]['cancel'].set()
    def wait(self,j,predicate,timeout,message):
        end=time.monotonic()+timeout
        while True:
            if self.closed.is_set() or j['cancel'].is_set():raise Cancelled('操作已取消')
            value=predicate()
            if value:return value
            if time.monotonic()>=end:raise TimeoutError(message)
            self.closed.wait(.03)
    def delay(self,j,seconds):
        end=time.monotonic()+seconds;self.wait(j,lambda:time.monotonic()>=end,seconds+1,'等待超时')
    def ack(self,j,ticket,timeout=10):
        def done():
            result=self.engine.command_result(ticket)
            if result['state']=='failed':raise RuntimeError(result.get('error','设备拒绝命令'))
            return result if result['state'] in ('acknowledged','simulated') else None
        result=self.wait(j,done,timeout,'设备应答超时，请检查连接与固件')
        self.update(j,'simulated' if result['state']=='simulated' else 'acknowledged',
                    '模拟命令完成（非设备应答）' if result['state']=='simulated' else '设备已应答')
        return result
    def _work(self):
        while not self.closed.is_set():
            try:j=self.queue.get(timeout=.1)
            except queue.Empty:continue
            self.active=j['id']
            try:
                if j['action']=='capture' and self.engine.capabilities.get('duo_mouse'):
                    with self.lock:self.start_aux(j)
                else:self.run_job(j)
            finally:self.active=None
    def snapshot(self):
        e=self.engine
        with e.lock:
            return dict(source=e.source,ready=e.ready,status=e.status,device=e.device,
                        baud=e.serial.baudrate if e.serial else None,capabilities=e.capabilities,voices=[dict(v) for v in e.voices],stats=e.stats(),
                        piano_settings=[dict(v) for v in e.piano_settings],capture_revision=e.audio_revision,active_job=self.active,api_version=1,
                        channels=list(e.channel_names),capture_metadata=dict(e.audio_metadata),duo=e.duo_snapshot())
    def reports(self):
        s=self.engine.imu.snapshot()
        return dict(source=self.engine.source,mode=self.engine.mode,counts=dict(s['counts']),
                    confirmed=dict(s['confirmed']),failures=dict(s['failures']),
                    latest={kind:dict(values=list(v.values),age_ms=(time.perf_counter_ns()-ns)/1e6) for kind,(ns,v) in s['latest'].items()},
                    raw=list(self.engine.raw))
    def audio(self):
        with self.engine.lock:
            if self.engine.audio is None:raise ValueError('没有完整采样；请先抓取')
            return self.engine.audio.copy(),self.engine.fs
    def capture_info(self):
        with self.engine.lock:
            a,fs=self.audio();e=self.engine
            return dict(source=e.source,revision=e.audio_revision,sample_rate=fs,shape=list(a.shape),samples=a.tolist(),voice_samples=e.voice_audio.tolist() if e.voice_audio is not None else None,monitor_voices=list(e.audio_metadata.get('monitor_voices',[])),channels=list(e.channel_names),metadata=dict(e.audio_metadata))
    def spectrum_info(self,channel):
        if channel not in range(5):raise ValueError('通道编号必须为 0～4（4 为混音）')
        a,fs=self.audio();f,db,phase=spectrum(a[:,channel],fs)
        return dict(channel=channel,sample_rate=fs,source=self.engine.source,frequency_hz=f.tolist(),
                    amplitude_dbfs=db.tolist(),phase_deg=[None if np.isnan(v) else float(v) for v in phase])
    def output_dir(self,name=None):
        base=(self.root/'agent-results').resolve();base.mkdir(exist_ok=True)
        name=name or time.strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]
        path=(base/name).resolve()
        if not path.is_relative_to(base) or path==base:raise ValueError('输出目录必须位于 agent-results 内')
        path.mkdir(parents=True,exist_ok=False);return path
    @staticmethod
    def write_audio(path,a,fs,channels=None):
        with Path(path).open('w',newline='',encoding='utf-8-sig') as out:
            w=csv.writer(out);w.writerow(['时间_s',*(channels or ['声部一','声部二','声部三','声部四','混音'])])
            for i,row in enumerate(a):w.writerow([i/fs,*map(int,row)])
    def export_to(self,path):
        with self.engine.lock:
            a,fs=self.audio();e=self.engine;m=dict(e.audio_metadata);names=list(e.channel_names);source=e.source
            v=e.voice_audio.copy() if e.voice_audio is not None else None
        self.write_audio(path/'采样.csv',a,fs,names)
        if v is not None and v.shape[1]:self.write_audio(path/'所选声部PCM.csv',v,fs,[f'声部{i+1}' for i in m.get('monitor_voices',[])])
        (path/'采样元数据.json').write_text(json.dumps(dict(m,channels=names,source=source),ensure_ascii=False,indent=2),encoding='utf-8')
        for c in range(5):
            f,db,phase=spectrum(a[:,c],fs)
            with (path/f'幅相谱-{c}.csv').open('w',encoding='utf-8-sig',newline='') as out:
                w=csv.writer(out);w.writerow(['频率_Hz','幅度_dBFS','相位_度'])
                w.writerows((float(x),float(y),'' if np.isnan(z) else float(z)) for x,y,z in zip(f,db,phase))
        (path/'统计.json').write_text(json.dumps(self.snapshot(),ensure_ascii=False,indent=2),encoding='utf-8')
        return dict(directory=str(path),shape=list(a.shape),sample_rate=fs)
    def voices(self,j,values):
        if not isinstance(values,list) or not 1<=len(values)<=4:raise ValueError('voices 必须包含 1～4 路参数')
        prepared=[]
        for item in values:
            c=item.get('channel')
            if type(c) is not int or c not in range(4):raise ValueError('声部编号 channel 为 0～3')
            extras={k:item[k] for k in ('piano_hold','piano_decay_s') if k in item}
            piano=dict(self.engine.piano_settings[c]);piano.update(extras)
            if extras:
                P.piano_payload(c,piano['piano_hold'],piano['piano_decay_s'],self.engine.fs)
                if not self.engine.capabilities.get('piano_control'):raise ValueError('钢琴保持/衰减调整需要TangLab 1.3固件，请先下载配套新固件')
            settings=dict(self.engine.voices[c]);settings.update({k:v for k,v in item.items() if k not in ('channel','piano_hold','piano_decay_s')})
            if set(settings)!=set(self.engine.voices[c]):raise ValueError('未知声部参数')
            for k,lo,hi in [('hz',1,20000),('gain',0,1),('attack',0,5000),('decay',0,5000),('sustain',0,1),('release',0,5000)]:
                if not isinstance(settings[k],(int,float)) or not math.isfinite(settings[k]) or not lo<=settings[k]<=hi:raise ValueError(f'{k} 参数超出范围')
            if type(settings['gate']) is not bool or type(settings['wave']) is not int or settings['wave'] not in range(5):raise ValueError('gate 使用布尔值，wave 使用 0～4（4为钢琴，需要固件1.2）')
            prepared.append((c,settings,piano if extras else None))
        for c,settings,piano in prepared:
            if piano is not None:
                self.ack(j,self.engine.send(P.PIANO_CONFIG,P.piano_payload(c,piano['piano_hold'],piano['piano_decay_s'],self.engine.fs)))
                self.engine.apply_piano_settings(c,piano)
            self.ack(j,self.engine.set_voice(c,settings))
        return dict(voices=[dict(v) for v in self.engine.voices],piano_settings=[dict(v) for v in self.engine.piano_settings],source=self.engine.source)
    def capture(self,j,trigger=0,points=2048):
        if trigger not in (0,1):raise ValueError('trigger 必须为 0（立即）或 1（上升过零）')
        if type(points) is not int or points not in (512,2048):raise ValueError('完整采样点数必须为512或2048')
        e=self.engine;started=time.monotonic();revision=e.audio_revision
        if points==512 and 512 not in e.capabilities.get('capture_sizes',[]):raise ValueError('快速512点采集需要TangLab 1.3固件；当前仍可使用2048点')
        crc,gaps=e.parser.errors,e.gaps;previous_id=e.capture_id
        d=dict(job=j['id'],request_time=time.time(),trigger=trigger,points=points,source=e.source,state='请求中',ack_ms=None,receive_ms=None,draw_ms=None,receive_to_draw_ms=None)
        with e.lock:e.capture_diagnostics.append(d)
        try:
            payload=bytes([trigger]) if points==2048 else struct.pack('<BH',trigger,points)
            ticket=e.send(P.CAPTURE,payload);d['sequence']=ticket
            result=self.ack(j,ticket)
            d['ack_ms']=max(0,(result.get('ack_at',time.monotonic())-started)*1000);d['state']='等待完整数据'
            self.update(j,'simulated' if result['state']=='simulated' else 'acknowledged','等待完整采样（尚未完成）')
            def complete():
                if not e.ready:raise ConnectionError('通信失败：设备已断开，请检查USB和串口后重新连接')
                return e.audio_revision>revision and (not e.capabilities.get('duo_mouse') or e.audio_metadata.get('event_id')==0 and len(e.audio)==points)
            try:self.wait(j,complete,self.capture_timeout_s,'采集等待超时')
            except TimeoutError:
                with e.lock:
                    rows=sum(len(block) for block in e.capture_parts.values()) if e.capture_id!=previous_id else 0
                    total=e.capture_total
                if e.capabilities.get('duo_monitor') and e.bus_complete:
                    raise TimeoutError('报文不完整：五路输出已到达，所选声部或采样元数据未收齐；原波形已保留，请检查CRC/缺包统计') from None
                if rows:
                    raise TimeoutError(f'报文不完整：收到 {rows}/{total} 点；请检查串口传输及CRC/缺包统计，原波形已保留') from None
                if trigger:
                    raise TimeoutError('过零触发等待超时：静音或钢琴衰减后可能无过零；请复位FPGA并重新连接，改用立即触发。上位机无法取消板上等待') from None
                raise TimeoutError('立即抓取超时：未收到完整样本；请检查CRC/缺包、USB及串口。若此前用过过零触发，请复位FPGA后重新连接') from None
            a,fs=self.audio();received=e.audio_received_at or time.monotonic()
            if len(a)!=points:raise ValueError(f'完整采样点数与请求不符：请求{points}，收到{len(a)}')
            d.update(state='完整数据已到达',revision=e.audio_revision,received_at=received,receive_ms=max(0,(received-started)*1000),silent=not bool(np.any(a)))
            # The GUI may already have painted while the worker was waking up.
            if getattr(e,'last_draw_revision',None)==e.audio_revision:
                d['draw_ms']=e.last_draw_ms;d['receive_to_draw_ms']=max(0,(e.last_draw_at-received)*1000)
            return dict(revision=e.audio_revision,shape=list(a.shape),sample_rate=fs,source=e.source,silent=d['silent'],timing=d)
        except Exception as exc:
            d.update(state='失败',error=str(exc));raise
        finally:
            d.update(crc_delta=e.parser.errors-crc,missing_delta=e.gaps-gaps,total_ms=(time.monotonic()-started)*1000)
            self.events.append(f"采集诊断：{d['state']}；应答 {d['ack_ms']} ms；收齐 {d['receive_ms']} ms；CRC +{d['crc_delta']}，缺包 +{d['missing_delta']}")
            if e.recorder:e.recorder.put(dict(type='capture_diagnostic',**d))
    def preview(self,j,enabled):
        self.ack(j,self.engine.send(P.PREVIEW,bytes([bool(enabled)])))
        if enabled:
            self.engine.envelope.clear()
            if self.engine.source.startswith('模拟'):
                self.engine.make_demo_audio();a=self.engine.audio
                for off in range(0,len(a),480):
                    block=a[off:off+480];self.engine.envelope.append((off,np.column_stack((block.min(axis=0),block.max(axis=0)))))
            self.engine.audio=None
        return dict(enabled=bool(enabled))
    def configure(self,j,settings):
        if not settings or any(k not in (1,2,4,5,8,40) or not isinstance(v,(int,float)) or not 0<=v<=400 for k,v in settings.items()):raise ValueError('报告编号或频率无效（0～400 Hz，0 为关闭）')
        if self.engine.source.startswith('模拟'):raise ValueError('模拟模式不伪造 SPI 传感器配置应答')
        for ticket in self.engine.configure_imu(settings):self.ack(j,ticket)
        self.wait(j,lambda:all(k in self.engine.imu.snapshot()['confirmed'] for k in settings),8,'传感器配置没有完整应答；FPGA ACK 不代表传感器应答')
        result=self.reports()
        if result['failures']:raise ValueError('传感器配置异常：'+str(result['failures']))
        if any((result['confirmed'][k]==0)!=(hz==0) for k,hz in settings.items()):raise ValueError('传感器启停状态与请求不符')
        return result
    def execute(self,j,action,p):
        e=self.engine
        if action=='instrument.demo':
            e.demo_duo();e.device='DUO04-LIVE 2.0 模拟';e.source='模拟演示（DUO04，非板卡实测）';e.enable_duo_capabilities();e.instrument_state=dict(mode=0,position=0,correct=0,wrong=0,online=0,target_note=60,target_hand=0);return self.snapshot()
        if action=='instrument.set':
            from lab_instrument import execute as execute_instrument
            return execute_instrument(self,j,p)
        if action.startswith(('monitor.','sine.')):
            from lab_monitor import execute_monitor
            return execute_monitor(self,j,action,p)
        if action=='duo.expression':
            from lab_expression import execute_expression
            return execute_expression(self,j,p)
        if action.startswith('duo.'):return execute_duo(self,j,action,p)
        if action=='connect':
            if e.recorder:raise ValueError('请先停止记录')
            self.ack(j,e.connect(str(p['port']),p.get('baud',921600)));return self.snapshot()
        if action=='disconnect':e.close();return self.snapshot()
        if action=='demo':
            if e.recorder:raise ValueError('请先停止记录')
            e.demo();return self.snapshot()
        if action=='voices.set':return self.voices(j,p['voices'])
        if action=='voices.release':return self.voices(j,[dict(channel=i,gate=False) for i in range(4)])
        if action=='capture':return self.capture(j,p.get('trigger',0),p.get('points',2048))
        if action=='preview':return self.preview(j,p.get('enabled',True))
        if action=='imu.mode':
            mode=p.get('mode',2)
            if mode not in (0,1,2):raise ValueError('模式编号：0 RVC、1 SHTP、2 SPI')
            self.ack(j,e.set_mode(mode));self.delay(j,2);return dict(mode=mode,note='已复位，尚需配置报告并检查传感器应答')
        if action=='imu.configure':return self.configure(j,{int(k):v for k,v in p.get('reports',{'5':100,'1':100,'2':100}).items()})
        if action=='ping':self.ack(j,e.send(P.PING));return e.stats()['pc_roundtrip_ms']
        if action=='record.start':
            if e.recorder:raise ValueError('正在记录，请先停止')
            directory=self.output_dir(p.get('name'))/'recording';e.start_record(directory);return dict(directory=str(directory))
        if action=='record.stop':e.stop_record();return dict(stopped=True)
        if action=='replay':
            if e.recorder:raise ValueError('请先停止记录')
            e.replay(p['path']);self.wait(j,lambda:e.status in ('回放完成',) or e.status.startswith('回放失败'),180,'回放超时')
            if e.status.startswith('回放失败'):raise ValueError(e.status)
            return self.snapshot()
        if action=='export':return self.export_to(self.output_dir(p.get('name')))
        if action.startswith('eda.'):
            if not self.ui_call:raise ValueError('没有 GUI 工程上下文')
            if action=='eda.stop':return self.ui_call('stop')
            self.ui_call('build' if action=='eda.build' else 'synthesis')
            try:
                end=time.monotonic()+600
                while True:
                    result=self.ui_call('status')
                    if not result['running']:
                        if result['exit_code']!=0:raise RuntimeError('编译失败：'+result['log'][-2000:])
                        return result
                    if time.monotonic()>end:raise TimeoutError('编译超过 10 分钟，已请求停止')
                    self.delay(j,.2)
            except Exception:self.ui_call('stop');raise
        if action=='test.two_voice_spi':
            from lab_board_test import run_test
            return run_test(self,j,p)
        raise ValueError('未知操作')
    def shutdown(self):
        self.closed.set()
        with self.lock:
            for j in self.jobs.values():j['cancel'].set()
        self.worker.join(5)
        for t in list(self.aux_workers):t.join(1)

class AgentServer:
    def __init__(self,controller):self.controller=controller;self.http=None;self.session_path=controller.root/'.agent-session.json'
    def start(self):
        if self.http:return self.info
        service=self;token=secrets.token_urlsafe(32)
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def reply(self,code,data):
                wire=json.dumps(data,ensure_ascii=False,allow_nan=False).encode('utf-8')
                self.send_response(code);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(wire)));self.end_headers()
                try:self.wfile.write(wire)
                except (BrokenPipeError,ConnectionResetError):pass
            def handle_request(self,post=False):
                if self.headers.get('Origin') or not secrets.compare_digest(self.headers.get('Authorization',''),'Bearer '+token):
                    self.reply(401,dict(error='令牌无效或浏览器跨源请求被拒绝'));return
                try:
                    path=urlsplit(self.path).path;c=service.controller
                    if post:
                        n=int(self.headers.get('Content-Length','0'))
                        if not 0<n<=65536:raise ValueError('请求体必须为 1～65536 字节')
                        data=json.loads(self.rfile.read(n))
                        if path=='/api/v1/commands':result=c.submit(data['action'],data.get('params',{}))
                        elif path.startswith('/api/v1/jobs/') and path.endswith('/cancel'):
                            key=path.split('/')[-2];c.cancel(key);result=c.job(key)
                        else:self.reply(404,dict(error='接口不存在'));return
                        self.reply(202,result);return
                    if path=='/api/v1/status':result=c.snapshot()
                    elif path=='/api/v1/capabilities':result=dict(api_version=1,commands=COMMANDS,hardware=c.engine.capabilities)
                    elif path=='/api/v1/ports':
                        from serial.tools.list_ports import comports
                        result=[dict(port=p.device,description=p.description) for p in comports()]
                    elif path=='/api/v1/reports':result=c.reports()
                    elif path=='/api/v1/capture':result=c.capture_info()
                    elif path.startswith('/api/v1/spectrum/'):result=c.spectrum_info(int(path.rsplit('/',1)[-1]))
                    elif path.startswith('/api/v1/jobs/'):result=c.job(path.rsplit('/',1)[-1])
                    elif path=='/api/v1/events':result=list(c.events)
                    elif path=='/api/v1/eda':
                        if not c.ui_call:raise ValueError('没有 GUI 工程上下文')
                        result=c.ui_call('status')
                    else:self.reply(404,dict(error='接口不存在'));return
                    self.reply(200,result)
                except KeyError as exc:self.reply(404,dict(error='缺少字段或任务不存在：'+str(exc)))
                except Exception as exc:self.reply(400,dict(error=str(exc)))
            def do_GET(self):self.handle_request()
            def do_POST(self):self.handle_request(True)
            def setup(self):super().setup();self.connection.settimeout(5)
        try:self.http=LocalHTTPServer(('127.0.0.1',18738),Handler)
        except OSError:self.http=LocalHTTPServer(('127.0.0.1',0),Handler)
        self.http.daemon_threads=True
        self.info=dict(url=f'http://127.0.0.1:{self.http.server_port}',token=token,api_version=1)
        self.session_path.write_text(json.dumps(self.info),encoding='utf-8')
        self.thread=threading.Thread(target=self.http.serve_forever,kwargs=dict(poll_interval=.1),daemon=True);self.thread.start();return self.info
    def stop(self):
        if not self.http:return
        with self.controller.lock:
            for j in self.controller.jobs.values():
                if j['state'] not in ('completed','failed','cancelled'):j['cancel'].set()
        self.http.shutdown();self.http.server_close();self.thread.join(1);self.http=None
        self.session_path.unlink(missing_ok=True)
