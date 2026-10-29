"""DUO02 1.3 atomic bus/selected-voice capture and direct calibration commands."""
import math,struct,time
import numpy as np
MONITOR_SELECT,SINE_START,SINE_STOP=54,55,56
VOICE_DATA,VOICE_META=138,139

def monitor_payload(params):
    ids=params.get('voices',[0,16])
    if set(params)-{'voices'} or not isinstance(ids,list) or len(ids)>4 or any(type(i) is not int or not 0<=i<32 for i in ids) or len(set(ids))!=len(ids):raise ValueError('voices为最多4个不重复的声部编号0～31')
    return bytes([len(ids),*ids,*([255]*(4-len(ids)))])

def sine_payload(params,fs=48000):
    if set(params)-{'frequency_hz','level_dbfs','channels'}:raise ValueError('未知正弦测试参数')
    f=params.get('frequency_hz',1000);db=params.get('level_dbfs',-30);ch=params.get('channels','both')
    if type(f) not in (int,float) or not math.isfinite(f) or not 20<=f<=10000:raise ValueError('频率范围20～10000 Hz')
    if type(db) not in (int,float) or not math.isfinite(db) or not -60<=db<=-6:raise ValueError('测试电平范围−60～−6 dBFS')
    if ch not in ('left','right','both'):raise ValueError('channels为left/right/both')
    return struct.pack('<BIHB',1,round(f/fs*2**32),round(32767*10**(db/20)),{'left':1,'right':2,'both':3}[ch])

class MonitorEngineMixin:
    def reset_monitor(self):
        self.monitor_ids=[0,16];self.voice_audio=None;self.monitor_meta={};self.voice_parts={};self.bus_complete={};self.monitor_fs={}
        self.sine_state=dict(mode=False,enabled=False,active=False,frequency_hz=1000.,level_dbfs=-30.,channels='both')
    def monitor_frame(self,f):
        p=f.payload
        if f.kind==VOICE_META:
            if len(p)!=16:raise ValueError('声部元数据长度错误')
            cid,count=struct.unpack_from('<HB',p);ids=list(p[3:3+count]);mode=p[7]
            if count>4 or len(set(ids))!=count or any(i>=32 for i in ids) or mode not in (0,1):raise ValueError('声部元数据无效')
            word,amp,ch=struct.unpack_from('<IHB',p,8)
            self.monitor_meta[cid]=dict(monitor_voices=ids,calibration=bool(mode),frequency_hz=word*self.fs/2**32,level_dbfs=20*math.log10(amp/32767) if amp else None,calibration_channels={1:'left',2:'right',3:'both'}.get(ch,'none'))
            for mapping in (self.monitor_meta,self.voice_parts,self.bus_complete,self.monitor_fs):
                while len(mapping)>16:mapping.pop(next(iter(mapping)))
            self.finish_monitor_capture(cid);return True
        if f.kind!=VOICE_DATA:return False
        if len(p)<10:raise ValueError('声部数据头不足')
        cid,off,total,fs=struct.unpack_from('<HHHI',p);m=self.monitor_meta.get(cid)
        if not m or not m['monitor_voices']:raise ValueError('声部数据缺少元数据')
        n=len(m['monitor_voices'])
        if not 0<total<=4096 or fs<=0 or (len(p)-10)%(n*2):raise ValueError('声部采样长度错误')
        rows=np.frombuffer(p[10:],dtype='<i2').reshape(-1,n).copy()
        if not len(rows) or off+len(rows)>total:raise ValueError('声部采样越界')
        signature=(total,fs)
        if cid in self.monitor_fs and self.monitor_fs[cid]!=signature:raise ValueError('同次声部采样格式不一致')
        self.monitor_fs[cid]=signature;parts=self.voice_parts.setdefault(cid,{})
        if off in parts and not np.array_equal(parts[off],rows):raise ValueError('重复声部片段不一致')
        parts[off]=rows;self.finish_monitor_capture(cid);return True
    def finish_monitor_capture(self,cid):
        m=self.monitor_meta.get(cid);bus=self.bus_complete.get(cid)
        if m is None or bus is None or cid not in self.capture_metadata:return
        a,fs=bus;n=len(m['monitor_voices']);voices=np.empty((len(a),0),np.int16)
        if n:
            if self.monitor_fs.get(cid)!=(len(a),fs):return
            at=0;blocks=[]
            for off,block in sorted(self.voice_parts.get(cid,{}).items()):
                if off!=at:return
                at+=len(block);blocks.append(block)
            if at!=len(a):return
            voices=np.concatenate(blocks)
        self.audio=a;self.voice_audio=voices;self.fs=fs;self.audio_metadata=dict(self.capture_metadata[cid],**m)
        if self.capabilities.get('instrument'):self.audio_metadata['host_context_at_receive']=dict(instrument=dict(self.instrument_state),config=dict(self.duo_config))
        self.audio_revision+=1;self.audio_received_at=time.monotonic();self.remember_audio()
        self.status=f'采样完成 {len(a)} 点 × {5+n} 通道'+(' · 校准正弦' if m['calibration'] else '')
        for mapping in (self.bus_complete,self.monitor_meta,self.voice_parts,self.monitor_fs):mapping.pop(cid,None)

def execute_monitor(c,j,action,p):
    e=c.engine
    if not e.ready or not e.capabilities.get('duo_monitor'):raise ValueError('此功能需要DUO02-MOUSE 1.3（32声部调试）固件')
    if action=='monitor.select':
        wire=monitor_payload(p);c.ack(j,e.send(MONITOR_SELECT,wire));e.monitor_ids=list(wire[1:1+wire[0]])
        return dict(accepted=True,voices=e.monitor_ids,effective='下一次采集')
    from lab_duo import DUO_STOP
    if action=='sine.start':
        wire=sine_payload(p,e.fs)
        c.wait(j,lambda:not any(q['action']=='capture' and q['state'] in ('running','acknowledged','simulated') for q in list(c.jobs.values())),c.capture_timeout_s+1,'等待在途抓取结束超时')
        c.ack(j,e.send(DUO_STOP));e.duo_config['run']=False;e.duo['running']=False
        # Stop effects and let the existing gain ramp and note cancellation finish.
        c.wait(j,lambda:not e.duo.get('active_mask') and not e.duo.get('actual_gain') and not e.sine_state.get('active'),3,'等待约5ms静音及演奏清理超时')
        c.ack(j,e.send(SINE_START,wire))
        _,word,amp,ch=struct.unpack('<BIHB',wire)
        e.sine_state=dict(mode=True,enabled=True,active=True,frequency_hz=word*e.fs/2**32,level_dbfs=20*math.log10(amp/32767),channels={1:'left',2:'right',3:'both'}[ch])
        return dict(accepted=True,calibration=dict(e.sine_state),source=e.source)
    if action=='sine.stop':
        c.ack(j,e.send(SINE_STOP));e.sine_state['enabled']=False
        return dict(accepted=True,note='约5ms渐变停止，保持静音')
    raise ValueError('未知监测命令')
