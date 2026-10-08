import json,queue,struct,threading,time,math
from collections import deque
from pathlib import Path
import numpy as np
import lab_protocol as P
from engine import Engine,Recorder
from protocol import encode_packet,set_feature

class LabEngine:
    def __init__(self):
        self.lock=threading.RLock();self.stop=threading.Event();self.thread=None;self.serial=None
        self.imu=Engine();self.recorder=None;self.reset()
    def reset(self):
        self.command_results={};self.demo_rxseq=0;self.capabilities=dict(voices=4,capture_points=2048,protocol=1)
        self.parser=P.Parser();self.tx=queue.Queue(256);self.seq=0;self.rxseq=None;self.gaps=0;self.frames=0
        self.status='未连接';self.source='未连接';self.ready=False;self.mode=0;self.device='—';self.fs=48000;self.clock=50000000
        self.audio=None;self.audio_revision=0;self.envelope=deque(maxlen=500);self.capture_parts={};self.capture_id=None
        self.capture_total=0;self.audio_received_at=0;self.capture_diagnostics=deque(maxlen=30)
        self.last_draw_revision=None;self.last_draw_at=0;self.last_draw_ms=0
        self.audio_history=deque(maxlen=30);self.audio_count=0;self.audio_origin=time.monotonic();self.audio_session=object()
        self.bus=deque(maxlen=20000);self.processing=deque(maxlen=20000);self.rtt=deque(maxlen=20000)
        self.raw=deque(maxlen=30);self.pending={};self.onwire=None;self.retry_at=0;self.retry_count=0;self.bytes=0;self.started=time.monotonic();self.drops=0;self.clips=0;self.config={}
        self.voices=[dict(hz=h,gain=.002,wave=0,gate=False,attack=10,decay=80,sustain=.7,release=180) for h in (375,750,1125,1500)]
        self.piano_settings=[dict(piano_hold=False,piano_decay_s=6.) for _ in range(4)]
        self.demo_note_start=[time.monotonic()]*4
        self.demo_body_at=[time.monotonic()]*4;self.demo_body_level=[1.]*4
        self.imu.disconnect();self.imu.reset_state();self.imu.protocol='UART-RVC';self.imu.source='FPGA 转发';self.imu_seq=0
    def close(self):
        self.stop.set()
        self.imu.disconnect()
        if self.serial:
            try:self.serial.cancel_read()
            except Exception:pass
        if self.thread:self.thread.join(3)
        if self.serial:self.serial.close()
        self.serial=None;self.thread=None;self.ready=False
        self.stop_record();self.status='已断开'
    def connect(self,port,baud=921600):
        import serial
        if type(baud) is not int or baud not in (115200,230400,460800,921600,1000000,1500000,2000000,3000000):raise ValueError('不支持的波特率')
        self.close();self.reset();self.stop.clear()
        self.serial=serial.Serial(port,baud,timeout=.02,write_timeout=.5)
        # Windows 默认接收队列不足以容纳完整抓取的突发数据。
        if hasattr(self.serial, 'set_buffer_size'):
            self.serial.set_buffer_size(rx_size=65536, tx_size=4096)
        self.source='真实 FPGA / '+port;self.status='等待握手'
        self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start();return self.send(P.HELLO)
    def send(self,kind,payload=b''):
        if self.source.startswith('模拟'):
            if kind==P.CAPTURE:self.make_demo_audio(struct.unpack_from('<H',payload,1)[0] if len(payload)==3 else 2048);self.record_demo_capture()
            with self.lock:
                seq=self.seq;self.seq=(seq+1)&65535;self.command_results[seq]=dict(state='simulated',code=0)
            return seq
        if not self.serial or self.stop.is_set():raise ValueError('请先连接 FPGA')
        if kind!=P.HELLO and not self.ready:raise ValueError('尚未通过设备握手')
        with self.lock:
            seq=self.seq;self.seq=(seq+1)&65535
            self.tx.put_nowait((seq,kind,P.pack(kind,payload,seq)))
            self.command_results[seq]=dict(state='queued',kind=kind)
            if len(self.command_results)>512:self.command_results.pop(next(iter(self.command_results)))
            return seq
    def command_result(self,seq):
        with self.lock:return dict(self.command_results.get(seq,dict(state='unknown')))
    def run(self):
        try:
            while not self.stop.is_set():
                if not self.pending and time.monotonic()>=self.retry_at:
                    try:
                        if self.onwire is None:self.onwire=self.tx.get_nowait()
                        seq,kind,wire=self.onwire
                        self.serial.write(wire);self.pending[seq]=(kind,time.monotonic())
                        self.command_results[seq]=dict(state='sent',kind=kind)
                        if self.recorder:self.recorder.put(dict(type='tx',ns=time.perf_counter_ns(),hex=wire.hex()))
                    except queue.Empty:pass
                data=self.serial.read(max(1,min(8192,self.serial.in_waiting)))
                if data:self.ingest(data)
                with self.lock:
                    for seq,(kind,start) in list(self.pending.items()):
                        if time.monotonic()-start>5:
                            del self.pending[seq];self.onwire=None;self.status=f'命令 {kind:02X} 超时'
                            self.command_results[seq]=dict(state='failed',error='设备应答超时')
                            if kind==P.HELLO:self.ready=False
        except Exception as e:
            if not self.stop.is_set():self.status='连接失败/断开：'+str(e);self.ready=False
            for seq,result in list(self.command_results.items()):
                if result['state'] in ('queued','sent'):self.command_results[seq]=dict(state='failed',error=self.status)
            self.stop.set()
    def ingest(self,data):
        with self.lock:
            self.bytes+=len(data)
            if self.recorder:self.recorder.put(dict(type='rx',ns=time.perf_counter_ns(),hex=data.hex()))
            for f in self.parser.feed(data):
                if self.rxseq is not None:self.gaps+=(f.seq-self.rxseq-1)&65535
                self.rxseq=f.seq;self.frames+=1
                try:self.frame(f)
                except (ValueError,struct.error,IndexError) as e:self.parser.errors+=1;self.status='报文拒绝：'+str(e)
    def frame(self,f):
        p=f.payload
        if f.kind==P.INFO:
            request,self.clock,self.fs,voices,cap=struct.unpack_from('<HIIBH',p)
            if self.clock<=0 or self.fs<=0 or voices<4:raise ValueError('设备能力无效')
            self.device=p[13:].decode('ascii',errors='replace');self.ready=True;self.status='握手成功';self.pending.pop(request,None);self.onwire=None
            fixed=self.device in ('TangLab 1.1','TangLab 1.2','TangLab 1.3','TangLab 1.3.1');new=self.device in ('TangLab 1.3','TangLab 1.3.1')
            self.capabilities=dict(voices=voices,capture_points=cap,protocol=1,fine_gain=fixed,headphone_attenuation_db=30.103 if fixed else 0,piano=self.device in ('TangLab 1.2','TangLab 1.3','TangLab 1.3.1'),piano_control=new,capture_sizes=[512,2048] if new else [2048])
            self.command_results[request]=dict(state='acknowledged',code=0)
        elif f.kind in (P.ACK,P.PONG):
            request,code=struct.unpack_from('<HB',p)
            old=self.pending.pop(request,None)
            if old is None:return
            if old and f.kind==P.PONG:self.rtt.append((time.monotonic()-old[1])*1000)
            if code==1 and self.onwire and self.retry_count<100:
                self.retry_count+=1;self.retry_at=time.monotonic()+.05;self.status='设备忙，等待重试'
            else:
                self.onwire=None;self.retry_count=0;self.status='命令完成' if code==0 else f'设备拒绝命令，错误码 {code}'
                self.command_results[request]=dict(state='acknowledged' if code==0 else 'failed',code=code,error='' if code==0 else self.status,ack_at=time.monotonic())
        elif f.kind==P.AUDIO:
            cid,offset,total,fs=struct.unpack_from('<HHHI',p)
            if total>4096 or total==0 or fs<=0 or (len(p)-10)%10:raise ValueError('抓取长度错误')
            rows=np.frombuffer(p[10:],dtype='<i2').reshape(-1,5).copy()
            if offset+len(rows)>total:raise ValueError('抓取越界')
            if self.capture_id!=cid:self.capture_id=cid;self.capture_parts={};self.capture_total=total
            if total!=self.capture_total:raise ValueError('同一次抓取的总长度不一致')
            self.capture_parts[offset]=rows
            at=0;blocks=[]
            for off,block in sorted(self.capture_parts.items()):
                if off!=at:return
                blocks.append(block);at+=len(block)
            if at==total:
                self.audio=np.concatenate(blocks);self.fs=fs;self.audio_revision+=1;self.audio_received_at=time.monotonic();self.remember_audio();self.status=f'完整抓取 {total} 点 × 5 通道'+(' · 当前采样为静音' if not np.any(self.audio) else '');self.capture_parts={}
        elif f.kind==P.ENVELOPE:
            if len(p)!=20:raise ValueError('包络长度错误')
            self.envelope.append((f.tick,np.frombuffer(p,dtype='<i2').reshape(5,2).copy()))
        elif f.kind==P.IMU:
            mode,start,end,parsed=struct.unpack_from('<BIII',p);raw=p[13:]
            if mode not in (0,1,2):raise ValueError('未知 IMU 模式')
            self.bus.append(((end-start)&0xffffffff)/self.clock*1000)
            self.processing.append(((parsed-end)&0xffffffff)/self.clock*1000)
            self.raw.append(raw.hex(' '));self.mode=mode
            self.imu.protocol='UART-RVC' if mode==0 else 'UART-SHTP'
            if mode==2:
                if len(raw)<4:raise ValueError('SPI SHTP 头不足')
                length,ch,seq=struct.unpack_from('<HBB',raw)
                if length!=len(raw):raise ValueError('SPI SHTP 长度/分片不支持')
                raw=encode_packet(ch,seq,raw[4:])
            self.imu.ingest(raw,time.perf_counter_ns())
        elif f.kind==P.STATUS:
            self.drops,self.clips=struct.unpack_from('<II',p)
    def set_voice(self,i,settings):
        if settings.get('wave')==4 and not self.source.startswith('模拟') and not self.capabilities.get('piano'):
            if settings.get('gate') and settings.get('gain',0)>0:raise ValueError('钢琴音色需要 TangLab 1.2 固件；请先下载钢琴版固件。')
            settings=dict(settings,wave=0)  # Muting an older firmware must remain possible.
        if not self.source.startswith('模拟') and not self.capabilities.get('fine_gain') and settings.get('gate') and settings.get('gain',0)>0:
            raise ValueError('旧固件未修正耳机输出时序；请先下载 TangLab 1.1 耳机修复固件。静音命令仍可使用。')
        if settings.get('gate') and (not self.voices[i]['gate'] or settings.get('wave')==4 and self.voices[i]['wave']!=4):
            self.demo_note_start[i]=time.monotonic();self.demo_body_at[i]=time.monotonic();self.demo_body_level[i]=1.
        seq=self.send(P.VOICE,P.voice_payload(i,**settings,fs=self.fs,fine_gain=self.capabilities.get('fine_gain',False)));self.voices[i]=settings.copy()
        if self.source.startswith('模拟'):self.make_demo_audio()
        return seq
    def apply_piano_settings(self,i,settings):
        now=time.monotonic();old=self.piano_settings[i]
        if old['piano_hold'] and self.voices[i]['gate']:self.demo_body_level[i]=1.
        else:self.demo_body_level[i]*=math.exp(math.log(.1)*max(0,now-self.demo_body_at[i])/old['piano_decay_s'])
        self.demo_body_at[i]=now;self.piano_settings[i]=dict(settings)
    def clear_waveforms(self):
        """Discard displayed audio data without changing voice parameters."""
        with self.lock:
            self.audio=None
            self.envelope.clear()
            self.capture_parts={}
            self.capture_id=None
            self.audio_history.clear();self.audio_count=0;self.audio_origin=time.monotonic()
            self.status='波形已清空'
    def remember_audio(self):
        self.audio_count+=1
        self.audio_history.append(dict(number=self.audio_count,received=time.time(),relative=time.monotonic()-self.audio_origin,fs=self.fs,samples=self.audio.copy()))
    def note_audio_drawn(self,revision,started):
        with self.lock:
            self.last_draw_revision=revision;self.last_draw_at=time.monotonic();self.last_draw_ms=(self.last_draw_at-started)*1000
            for d in reversed(self.capture_diagnostics):
                if d.get('revision')==revision and d.get('draw_ms') is None:
                    now=time.monotonic();d['draw_ms']=(now-started)*1000
                    d['receive_to_draw_ms']=max(0,(now-d['received_at'])*1000)
                    break
    def set_mode(self,mode):
        seq=self.send(P.MODE,bytes([mode]));self.mode=mode;self.bus.clear();self.processing.clear()
        self.imu.reset_state();self.imu.protocol='UART-RVC' if mode==0 else 'UART-SHTP'
        self.imu_seq=0
        return seq
    def configure_imu(self,settings):
        if self.mode==0:raise ValueError('RVC 固定 100 Hz，无报告配置')
        tickets=[]
        for rid,hz in settings.items():
            for cargo in (set_feature(rid,hz),bytes([0xfe,rid])):
                if self.mode==2:raw=struct.pack('<HBB',len(cargo)+4,2,self.imu_seq)+cargo
                else:raw=encode_packet(2,self.imu_seq,cargo)
                self.imu_seq=(self.imu_seq+1)&255;tickets.append(self.send(P.IMU_TX,raw))
            self.imu.config.request(rid,hz,time.monotonic())
        self.config=dict(settings)
        return tickets
    def demo(self):
        self.close();self.reset();self.source='模拟演示（非实测）';self.status='四声部模拟';self.ready=True
        for v in self.voices:v.update(gain=.18,gate=True)
        self.device='模拟固件 1.3';self.make_demo_audio();self.imu.simulate()
        self.capabilities.update(piano=True,piano_control=True,capture_sizes=[512,2048])
    def make_demo_audio(self,points=2048):
        t=np.arange(points)/self.fs;out=[]
        for i,v in enumerate(self.voices):
            phase=(t*v['hz'])%1
            if v['wave']==4:
                age=t+max(0,time.monotonic()-self.demo_note_start[i])
                fundamental=.5*np.sin(2*np.pi*phase)
                partial=sum((2.**-h)*np.sin(2*np.pi*h*phase) for h in (2,3,4) if h*v['hz']<self.fs/2)
                ps=self.piano_settings[i];now=time.monotonic();elapsed=max(0,now-self.demo_body_at[i])
                if ps['piano_hold'] and v['gate']:self.demo_body_level[i]=1.;body=np.ones_like(age)
                else:
                    self.demo_body_level[i]*=math.exp(math.log(.1)*elapsed/ps['piano_decay_s'])
                    body=self.demo_body_level[i]*np.exp(math.log(.1)*t/ps['piano_decay_s'])
                self.demo_body_at[i]=now
                shape=(fundamental+partial*np.exp(-age/.0853))*body
                attack=max(v['attack']/1000,1/self.fs);decay=max(v['decay']/1000,1/self.fs)
                envelope=np.where(age<attack,age/attack,np.maximum(v['sustain'],1-(age-attack)/decay))
                out.append(shape*envelope*32767*v['gain']*v['gate']);continue
            wave=(np.sin(2*np.pi*phase),2*phase-1,np.where(phase<.5,1.,-1.),1-4*np.abs(phase-.5))[v['wave']]
            out.append(wave*32767*v['gain']*v['sustain']*v['gate'])
        a=np.array(out).T;mix=a.sum(axis=1);self.clips=int(np.count_nonzero(np.abs(mix)>32767))
        self.audio=np.column_stack((a,np.clip(mix,-32768,32767))).astype(np.int16);self.audio_revision+=1;self.audio_received_at=time.monotonic();self.remember_audio()
    def start_record(self,path):
        if self.recorder:raise ValueError('正在记录')
        if not self.ready:raise ValueError('请先连接或模拟')
        self.recorder=Recorder(path,dict(format_version=2,protocol='TangLab-v1',source=self.source,mode=self.mode,clock=self.clock,fs=self.fs,config=self.config))
        self.record_demo_capture()
    def record_demo_capture(self):
        if not self.recorder:return
        if self.source.startswith('模拟'):
            # Record genuine wire-format simulated capture so replay exercises the decoder.
            if self.audio is None:
                for seq,(tick,values) in enumerate(self.envelope):
                    self.recorder.put(dict(type='rx',ns=time.perf_counter_ns(),hex=P.pack(P.ENVELOPE,values.astype('<i2').tobytes(),seq,tick).hex()))
                return
            for off in range(0,len(self.audio),32):
                payload=struct.pack('<HHHI',self.audio_revision&65535,off,len(self.audio),self.fs)+self.audio[off:off+32].astype('<i2').tobytes()
                self.recorder.put(dict(type='rx',ns=time.perf_counter_ns(),hex=P.pack(P.AUDIO,payload,self.demo_rxseq).hex()))
                self.demo_rxseq=(self.demo_rxseq+1)&65535
    def stop_record(self):
        with self.lock:r=self.recorder;self.recorder=None
        if r:r.close(self.stats())
    def replay(self,path):
        path=Path(path);meta=json.loads((path/'metadata.json').read_text(encoding='utf-8'))
        if meta.get('protocol')!='TangLab-v1':raise ValueError('旧 IMU 记录请通过“旧版直连工具”回放')
        self.close();self.reset();self.stop.clear();self.source='文件回放（非实时硬件）';self.clock=meta['clock'];self.fs=meta['fs']
        def run():
            try:
                first=None;start=time.monotonic()
                with (path/'raw.jsonl').open(encoding='utf-8') as f:
                    for line in f:
                        event=json.loads(line)
                        if event['type']!='rx':continue
                        if first is None:first=event['ns']
                        if self.stop.wait(max(0,(event['ns']-first)/1e9-(time.monotonic()-start))):return
                        self.ingest(bytes.fromhex(event['hex']))
                self.status='回放完成';self.ready=False
            except Exception as e:self.status='回放失败：'+str(e)
        self.thread=threading.Thread(target=run,daemon=True);self.thread.start()
    def stats(self):
        return dict(source=self.source,mode=self.mode,config=self.config,frames=self.frames,crc_errors=self.parser.errors,
                    missing_frames=self.gaps,loss_rate=self.gaps/max(1,self.frames+self.gaps),rx_bytes_per_s=self.bytes/max(.01,time.monotonic()-self.started),
                    board_drops=self.drops,clipping=self.clips,bus_ms=P.summary(self.bus),fpga_packet_ms=P.summary(self.processing),
                    pc_roundtrip_ms=P.summary(self.rtt),clock_hz=self.clock,sample_rate=self.fs,
                    note='各延迟测点不同；SPI/UART起点不同，不能解释为动作到音频延迟',
                    record_drops=self.recorder.dropped if self.recorder else 0,record_error=self.recorder.error if self.recorder else '',
                    capture_diagnostics=[dict(d) for d in self.capture_diagnostics])
