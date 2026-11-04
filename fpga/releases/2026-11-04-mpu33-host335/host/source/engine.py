"""Acquisition runs independently of GUI refresh. Every received batch has one host timestamp."""
import csv
import json
import math
import queue
import struct
import threading
import time
from collections import Counter, deque
from pathlib import Path
from dataclasses import asdict
from protocol import (RVCParser,SHTPParser,decode_reports,feature_response,
                      ConfigTracker,set_feature,encode_packet,from_euler,euler,POSE_IDS)

def percentiles(values):
    a=sorted(values)
    if not a: return '—'
    def at(p): return a[min(len(a)-1,round((len(a)-1)*p))]
    return ' / '.join(f'{v:.3f}' for v in (at(.5),at(.95),at(.99),a[-1]))

class Recorder:
    def __init__(self,path,metadata):
        self.path=Path(path); self.path.mkdir(parents=True,exist_ok=False)
        self.q=queue.Queue(16384); self.dropped=0; self.error=''; self.metadata=metadata
        self.thread=threading.Thread(target=self._run,daemon=True); self.thread.start()
    def put(self,event):
        try: self.q.put_nowait(event)
        except queue.Full: self.dropped+=1
    def _run(self):
        try:
            with (self.path/'raw.jsonl').open('w',encoding='utf-8') as raw, (self.path/'samples.csv').open('w',newline='',encoding='utf-8-sig') as f:
                w=csv.writer(f); w.writerow(['host_monotonic_ns','kind','sequence','accuracy','sensor_relative_offset_us','v0','v1','v2','v3','v4','v5'])
                while True:
                    event=self.q.get()
                    if event is None: break
                    if event['type']=='sample':
                        s=event['sample']; vals=list(s['values'])
                        w.writerow([event['ns'],s['kind'],s['seq'],s['accuracy'],s['sensor_offset_us']]+vals+['']*(6-len(vals)))
                    else: raw.write(json.dumps(event,ensure_ascii=False)+'\n')
        except Exception as exc: self.error=str(exc)
    def close(self,stats):
        while self.thread.is_alive():
            try: self.q.put(None,timeout=.1); break
            except queue.Full: continue
        self.thread.join(timeout=10)
        self.metadata.update(stats=stats,record_queue_dropped=self.dropped,error=self.error,
                             writer_finished=not self.thread.is_alive())
        (self.path/'metadata.json').write_text(json.dumps(self.metadata,ensure_ascii=False,indent=2),encoding='utf-8')

class Engine:
    def __init__(self):
        self.lock=threading.RLock(); self.stop=threading.Event(); self.threads=[]; self.serial=None
        self.recorder=None; self.source='未连接'; self.status='就绪'; self.protocol='UART-RVC'
        self.txq=queue.Queue(64); self.reset_state()
    def reset_state(self):
        self.rvc=RVCParser(); self.shtp=SHTPParser(); self.config=ConfigTracker()
        self.started=time.monotonic(); self.latest={}; self.history=deque(maxlen=30000)
        self.counts=Counter(); self.lastseq={}; self.gaps=Counter(); self.last_rx=None
        self.intervals=deque(maxlen=20000); self.parse_ms=deque(maxlen=20000)
        self.ui_ms=deque(maxlen=20000); self.events=deque(maxlen=100)
        self.config_desired={}; self.txseq=Counter(); self.device='尚未读取'; self.last_data_ns=0
        self.yaw_last=None; self.yaw_accum=0; self.yaw_min=0; self.yaw_max=0
    @property
    def running(self): return any(t.is_alive() for t in self.threads) and not self.stop.is_set()
    def _prepare(self,source,protocol):
        self.disconnect()
        with self.lock:
            self.reset_state(); self.stop.clear(); self.source=source; self.protocol=protocol
            self.txq=queue.Queue(64); self.status='启动中'
    def connect(self,port,protocol):
        import serial
        self._prepare('串口 '+port,protocol)
        try:
            s=serial.Serial(port=None,baudrate=115200 if protocol=='UART-RVC' else 3000000,
                            timeout=.05,write_timeout=1,rtscts=False,dsrdtr=False)
            s.dtr=False; s.rts=False; s.port=port; s.open(); self.serial=s
        except Exception as exc:
            self.status='连接失败：'+str(exc); self.stop.set(); raise
        self.status='串口已打开，等待有效报告'
        self.threads=[threading.Thread(target=self._rx,daemon=True),threading.Thread(target=self._tx,daemon=True)]
        for t in self.threads: t.start()
        if protocol=='UART-SHTP': self.txq.put((2,b'\xf9\x00',None))
    def disconnect(self):
        self.stop.set()
        if self.serial:
            try: self.serial.cancel_read()
            except Exception: pass
            try: self.serial.cancel_write()
            except Exception: pass
        for t in self.threads: t.join(timeout=2)
        if self.serial:
            try: self.serial.close()
            except Exception: pass
            self.serial=None
        self.threads=[]
        try: self.stop_recording(); self.status='已断开'
        except Exception as exc: self.status='已断开，记录收尾失败：'+str(exc)
    def _rx(self):
        try:
            while not self.stop.is_set():
                data=self.serial.read(min(max(1,self.serial.in_waiting),8192))
                if data: self.ingest(data,time.perf_counter_ns())
                else:
                    with self.lock:
                        self.config.expire(time.monotonic())
                        if self.last_rx and time.perf_counter_ns()-self.last_rx>1e9: self.shtp.expire()
        except Exception as exc:
            if not self.stop.is_set(): self.status='串口读取失败：'+str(exc); self.stop.set()
    def _tx(self):
        try:
            while not self.stop.is_set():
                try: ch,payload,request=self.txq.get(timeout=.1)
                except queue.Empty: continue
                with self.lock:
                    if request: self.config.request(*request,time.monotonic())
                    packet=encode_packet(ch,self.txseq[ch],payload); self.txseq[ch]=(self.txseq[ch]+1)&255
                for b in packet:
                    if self.stop.is_set(): return
                    self.serial.write(bytes([b])); self.serial.flush()
                    if self.stop.wait(.002): return
                with self.lock:
                    if self.recorder: self.recorder.put(dict(type='tx',ns=time.perf_counter_ns(),hex=packet.hex()))
        except Exception as exc:
            if not self.stop.is_set(): self.status='串口发送失败：'+str(exc); self.stop.set()
    def apply_config(self,settings):
        if self.protocol!='UART-SHTP' or not self.running or not self.source.startswith('串口'):
            raise ValueError('仅真实 UART-SHTP 连接支持写入配置')
        with self.lock:
            if self.config.pending or not self.txq.empty(): raise ValueError('已有命令正在发送，请等待应答/超时')
            # Stop unused reports before enabling the selected pose report.
            items=sorted(settings.items(),key=lambda pair: pair[1]!=0)
            self.config_desired=dict(settings)
            for rid,hz in items:
                self.txq.put_nowait((2,set_feature(rid,hz),(rid,hz)))
                self.txq.put_nowait((2,bytes((0xfe,rid)),None))
            if self.recorder: self.recorder.put(dict(type='config',ns=time.perf_counter_ns(),settings=settings))
    def ingest(self,data,ns):
        begin=time.perf_counter_ns()
        with self.lock:
            if self.last_rx is not None: self.intervals.append((ns-self.last_rx)/1e6)
            self.last_rx=ns; self.counts['rx_bytes']+=len(data); self.counts['rx_batches']+=1
            if self.recorder: self.recorder.put(dict(type='rx',ns=ns,hex=data.hex()))
            samples=[]
            if self.protocol=='UART-RVC': samples=self.rvc.feed(data)
            else:
                for ch,seq,payload in self.shtp.feed(data):
                    if ch in (3,4):
                        rows,err=decode_reports(payload); samples.extend(rows); self.counts['report_errors']+=err
                    elif ch==2:
                        response=feature_response(payload)
                        if response:
                            self.config.response(*response)
                            self.events.append(f'报告 0x{response[0]:02X} 返回间隔 {response[1]} μs')
                        elif payload[:1]==b'\xf8' and len(payload)>=14:
                            _,cause,major,minor,part,build,patch=struct.unpack_from('<BBBBIIH',payload)
                            self.device=f'部件 {part} / 固件 {major}.{minor}.{patch} / 构建 {build} / 复位原因 {cause}'
                    elif ch==1 and payload==b'\x01':
                        self.lastseq.clear(); self.latest.clear(); self.config=ConfigTracker(); self.shtp.seq.clear()
                        self.events.append('传感器复位完成：报告已停用，请重新应用配置')
                        self.status='传感器已复位，请重新应用配置'
            for s in samples:
                old=self.lastseq.get(s.kind)
                if old is not None and s.seq!=((old+1)&255): self.gaps[s.kind]+=1
                self.lastseq[s.kind]=s.seq; self.counts[s.kind]+=1
                self.latest[s.kind]=(ns,s); self.history.append((ns,s)); self.last_data_ns=ns
                if s.kind in ('rotation','stabilized','game','rvc'):
                    y=s.values[0] if s.kind=='rvc' else euler(s.values)[0]
                    if self.yaw_last is not None:
                        self.yaw_accum+=(y-self.yaw_last+180)%360-180
                        self.yaw_min=min(self.yaw_min,self.yaw_accum); self.yaw_max=max(self.yaw_max,self.yaw_accum)
                    self.yaw_last=y
                if self.recorder: self.recorder.put(dict(type='sample',ns=ns,sample=asdict(s)))
            if samples: self.status='正在接收有效报告'
            self.config.expire(time.monotonic())
            self.parse_ms.append((time.perf_counter_ns()-begin)/1e6)
    def snapshot(self):
        with self.lock:
            self.config.expire(time.monotonic())
            elapsed=max(.001,time.monotonic()-self.started)
            return dict(source=self.source,protocol=self.protocol,status=self.status,device=self.device,
                latest=dict(self.latest),history=list(self.history),counts=dict(self.counts),
                rates={k:v/elapsed for k,v in self.counts.items() if k not in ('rx_bytes','rx_batches','report_errors')},
                gaps=dict(self.gaps),parse_errors=self.rvc.errors+self.shtp.errors+self.counts['report_errors'],
                transport_gaps=self.shtp.sequence_gaps,unsupported_controls=self.shtp.controls,
                batch_ms=percentiles(self.intervals),parse_ms=percentiles(self.parse_ms),ui_ms=percentiles(self.ui_ms),
                batch_values=list(self.intervals),pending=dict(self.config.pending),confirmed=dict(self.config.confirmed),
                failures=dict(self.config.failures),desired=dict(self.config_desired),events=list(self.events),
                yaw_change=self.yaw_accum,yaw_range=self.yaw_max-self.yaw_min,
                recorder_dropped=self.recorder.dropped if self.recorder else 0,
                recorder_error=self.recorder.error if self.recorder else '',last_data_ns=self.last_data_ns)
    def start_recording(self,path):
        with self.lock:
            if self.recorder: raise ValueError('正在记录')
            if not self.running: raise ValueError('先启动采集或模拟')
            self.recorder=Recorder(path,dict(format_version=1,protocol=self.protocol,source=self.source,
                 started_local=time.strftime('%Y-%m-%d %H:%M:%S'),settings=self.config_desired,
                 time_note='host_monotonic_ns 属于 PC；sensor_relative_offset_us 为协议相对偏移，不是可与 PC 相减的绝对时间'))
    def stop_recording(self):
        with self.lock:
            r=self.recorder; self.recorder=None
            stats=dict(counts=dict(self.counts),gaps=dict(self.gaps),parse_errors=self.rvc.errors+self.shtp.errors,
                       config_confirmed=self.config.confirmed,config_failures=self.config.failures)
        if r:
            r.close(stats)
            if r.error: self.status='记录失败：'+r.error
    def simulate(self):
        self._prepare('模拟数据（非实测）','UART-SHTP')
        self.threads=[threading.Thread(target=self._simulate,daemon=True)]; self.threads[0].start()
    def _simulate(self):
        start=time.perf_counter(); n=0; seq=Counter()
        while not self.stop.is_set():
            due=start+n*.002
            if self.stop.wait(max(0,due-time.perf_counter())): break
            t=n*.002
            reports=[(1,(0.4*math.sin(t*3),0.2*math.cos(t),9.80665),8)]
            if n%5==0: reports.append((0x28,from_euler(70*math.sin(t*.4),25*math.sin(t),30*math.cos(t*.8)),14))
            if n%5==0: reports.append((2,(.1*math.sin(t),.2*math.cos(t),.3),9))
            for rid,vals,q in reports:
                payload=bytes((rid,seq[rid]&255,3,0))+struct.pack('<'+'h'*len(vals),*(round(x*(1<<q)) for x in vals))
                if rid==0x28: payload+=b'\x00\x00'
                self.ingest(encode_packet(3,seq['wire']&255,payload),time.perf_counter_ns())
                seq[rid]+=1; seq['wire']+=1
            n+=1
    def replay(self,path):
        path=Path(path); meta=json.loads((path/'metadata.json').read_text(encoding='utf-8'))
        if meta.get('protocol') not in ('UART-RVC','UART-SHTP'): raise ValueError('不支持的记录协议')
        if not (path/'raw.jsonl').is_file(): raise ValueError('缺少 raw.jsonl')
        self._prepare('回放（非实时硬件）',meta['protocol'])
        self.threads=[threading.Thread(target=self._replay,args=(path,),daemon=True)]; self.threads[0].start()
    def _replay(self,path):
        try:
            origin=None; begin=time.perf_counter_ns()
            with (path/'raw.jsonl').open(encoding='utf-8') as f:
                for line in f:
                    event=json.loads(line)
                    if event['type']!='rx': continue
                    if origin is None: origin=event['ns']
                    due=begin+event['ns']-origin
                    if self.stop.wait(max(0,(due-time.perf_counter_ns())/1e9)): return
                    self.ingest(bytes.fromhex(event['hex']),time.perf_counter_ns())
            self.status='回放完成'
        except Exception as exc: self.status='回放失败：'+str(exc)
