"""Loopback-only authenticated API and shared serial command scheduler."""
import csv,json,math,queue,secrets,threading,time,uuid
from collections import deque
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import numpy as np
import lab_protocol as P
from lab_ui import spectrum

STATES={'queued':'已排队','running':'执行中','acknowledged':'设备已应答','completed':'已完成',
        'failed':'失败','cancelled':'已取消','simulated':'模拟完成'}
COMMANDS=['connect','disconnect','demo','voices.set','voices.release','capture','preview',
          'imu.mode','imu.configure','ping','record.start','record.stop','replay','export',
          'eda.synthesis','eda.build','eda.stop','test.two_voice_spi']

class Cancelled(Exception):pass

class CommandController:
    def __init__(self,engine,root,ui_call=None):
        self.engine=engine;self.root=Path(root);self.ui_call=ui_call
        self.jobs={};self.lock=threading.RLock();self.queue=queue.Queue(64)
        self.events=deque(maxlen=100);self.active=None;self.closed=threading.Event()
        self.worker=threading.Thread(target=self._work,daemon=True);self.worker.start()
    def submit(self,action,params=None):
        if action not in COMMANDS:raise ValueError('未知命令：'+action)
        if not isinstance(params or {},dict):raise ValueError('params 必须是 JSON 对象')
        with self.lock:
            if len(self.jobs)>=200:
                for key,j in list(self.jobs.items()):
                    if j['state'] in ('completed','failed','cancelled'):del self.jobs[key];break
            j=dict(id=uuid.uuid4().hex,action=action,params=params or {},state='queued',message='已排队',
                   created=time.time(),cancel=threading.Event(),history=[])
            if action=='eda.stop' and self.active and self.jobs[self.active]['action'] in ('eda.build','eda.synthesis'):
                self.jobs[self.active]['cancel'].set()
            self.queue.put_nowait(j);self.jobs[j['id']]=j
            return self.job(j['id'])
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
                if j['cancel'].is_set():raise Cancelled('排队操作已取消')
                self.update(j,'running','执行中')
                result=self.execute(j,j['action'],j['params'])
                self.update(j,'cancelled' if j['cancel'].is_set() else 'completed',
                            '已取消，清理结果见任务输出' if j['cancel'].is_set() else ('数据已完成' if j['action'] in ('capture','replay','export') else '操作完成'),result=result)
            except Cancelled as exc:self.update(j,'cancelled',str(exc))
            except Exception as exc:self.update(j,'failed',str(exc))
            finally:self.active=None
    def snapshot(self):
        e=self.engine
        with e.lock:
            return dict(source=e.source,ready=e.ready,status=e.status,device=e.device,
                        baud=e.serial.baudrate if e.serial else None,capabilities=e.capabilities,voices=[dict(v) for v in e.voices],stats=e.stats(),
                        capture_revision=e.audio_revision,active_job=self.active,api_version=1)
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
        a,fs=self.audio()
        return dict(source=self.engine.source,revision=self.engine.audio_revision,sample_rate=fs,shape=list(a.shape),samples=a.tolist())
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
    def write_audio(path,a,fs):
        with Path(path).open('w',newline='',encoding='utf-8-sig') as out:
            w=csv.writer(out);w.writerow(['时间_s','声部一','声部二','声部三','声部四','混音'])
            for i,row in enumerate(a):w.writerow([i/fs,*map(int,row)])
    def export_to(self,path):
        a,fs=self.audio();self.write_audio(path/'采样.csv',a,fs)
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
            settings=dict(self.engine.voices[c]);settings.update({k:v for k,v in item.items() if k!='channel'})
            if set(settings)!=set(self.engine.voices[c]):raise ValueError('未知声部参数')
            for k,lo,hi in [('hz',1,20000),('gain',0,1),('attack',0,5000),('decay',0,5000),('sustain',0,1),('release',0,5000)]:
                if not isinstance(settings[k],(int,float)) or not math.isfinite(settings[k]) or not lo<=settings[k]<=hi:raise ValueError(f'{k} 参数超出范围')
            if type(settings['gate']) is not bool or type(settings['wave']) is not int or settings['wave'] not in range(4):raise ValueError('gate 使用布尔值，wave 使用 0～3')
            prepared.append((c,settings))
        for c,settings in prepared:self.ack(j,self.engine.set_voice(c,settings))
        return dict(voices=[dict(v) for v in self.engine.voices],source=self.engine.source)
    def capture(self,j,trigger=0):
        if trigger not in (0,1):raise ValueError('trigger 必须为 0（立即）或 1（上升过零）')
        revision=self.engine.audio_revision
        self.ack(j,self.engine.send(P.CAPTURE,bytes([trigger])))
        self.wait(j,lambda:self.engine.audio_revision>revision,15,'未收到完整采样；检查触发条件/传输。静音过零等待可用板上复位退出。')
        a,fs=self.audio()
        return dict(revision=self.engine.audio_revision,shape=list(a.shape),sample_rate=fs,source=self.engine.source)
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
        if action=='connect':
            if e.recorder:raise ValueError('请先停止记录')
            self.ack(j,e.connect(str(p['port']),p.get('baud',921600)));return self.snapshot()
        if action=='disconnect':e.close();return self.snapshot()
        if action=='demo':
            if e.recorder:raise ValueError('请先停止记录')
            e.demo();return self.snapshot()
        if action=='voices.set':return self.voices(j,p['voices'])
        if action=='voices.release':return self.voices(j,[dict(channel=i,gate=False) for i in range(4)])
        if action=='capture':return self.capture(j,p.get('trigger',0))
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
        try:self.http=ThreadingHTTPServer(('127.0.0.1',18738),Handler)
        except OSError:self.http=ThreadingHTTPServer(('127.0.0.1',0),Handler)
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
