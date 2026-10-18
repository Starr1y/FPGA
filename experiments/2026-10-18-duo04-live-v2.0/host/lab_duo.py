"""DUO02-MOUSE wire adapter; event acceptance and sampled data are distinct."""
import math,struct,time
from collections import deque
import numpy as np
import lab_protocol as P

DUO_CONFIG,DUO_SELECT,DUO_STRIKE,DUO_STOP,DUO_QUERY,DUO_HEARTBEAT=range(48,54)
DUO_STATUS,DUO_META=136,137
CHANNELS=['干声左','干声右','效果后左','效果后右','效果后混音']
LEGACY_CHANNELS=['声部一','声部二','声部三','声部四','混音']
PROFILES=[(0,2,4,5,7,9,11),(0,2,4,7,9),tuple(range(12))]
NAMES=[['DO','RE','MI','FA','SOL','LA','SI'],['DO','RE','MI','SOL','LA'],
       ['DO','DO#','RE','RE#','MI','FA','FA#','SOL','SOL#','LA','LA#','SI']]
PRESETS=['拨弦','贝斯','管乐','铃音','钢琴（合成）','正弦（演奏声部）']

def note_map(profile,zone,octave=0,chord=False):
    if type(profile) is not int or profile not in range(3) or type(zone) is not int or zone not in range(len(PROFILES[profile])):raise ValueError('音区编号超出当前布局')
    if type(octave) is not int or octave not in (-2,-1,0,1):raise ValueError('八度范围为 −2～1')
    base=60+12*octave;offset=PROFILES[profile][zone]
    if not chord:return [base+offset]
    if profile:return [base+offset+x for x in (0,4,7)]
    return [base+12*((zone+k)//7)+PROFILES[0][(zone+k)%7] for k in (0,2,4)]

def config_payload(params,extended=False,quality=False,instrument=False):
    d=dict(run=True,profiles=[0,0],presets=[0,0],chord=False,effect=0,wet=128,gain=32)
    if extended:d.update(hold_ms=[1500,1500],release_ids=[1,1])
    if quality:d.update(piano_hold=[False,False],piano_decay_s=[6.,6.])
    if set(params)-set(d):raise ValueError('未知鼠标测试配置项')
    d.update(params)
    for key,limit in [('profiles',3),('presets',6 if quality else 4)]:
        if not isinstance(d[key],list) or len(d[key])!=2 or any(type(x) is not int or x not in range(limit) for x in d[key]):raise ValueError(key+'必须为两个合法编号')
    if type(d['run']) is not bool or type(d['chord']) is not bool:raise ValueError('启用和和弦设置使用布尔值')
    for key,limit in [('effect',3),('wet',255),('gain',256 if extended else 64)]:
        if type(d[key]) is not int or not 0<=d[key]<=limit:raise ValueError(key+'超出范围')
    prefix=bytes([d['run'],*d['profiles'],*d['presets'],d['chord'],d['effect'],d['wet']])
    if not extended:return d,prefix+bytes([d['gain']])
    if not isinstance(d['hold_ms'],list) or len(d['hold_ms'])!=2 or any(type(x) is not int or not 100<=x<=(10000 if instrument else 5000) for x in d['hold_ms']):raise ValueError('保持时间范围：旧固件100～5000ms，DUO04为100～10000ms')
    if not isinstance(d['release_ids'],list) or len(d['release_ids'])!=2 or any(type(x) is not int or x not in range(3) for x in d['release_ids']):raise ValueError('释音编号为0/1/2，分别0.2/0.5/1.5秒')
    wire=prefix+struct.pack('<HHHB',d['gain'],*d['hold_ms'],d['release_ids'][0]|d['release_ids'][1]<<2)
    if quality:
        if not isinstance(d['piano_hold'],list) or len(d['piano_hold'])!=2 or any(type(x) is not bool for x in d['piano_hold']):raise ValueError('钢琴主体保持为左右两个布尔值')
        if not isinstance(d['piano_decay_s'],list) or len(d['piano_decay_s'])!=2 or any(type(x) not in (int,float) or not .2<=x<=30 for x in d['piano_decay_s']):raise ValueError('钢琴衰减至10%为左右各0.2～30秒')
        coefficients=[round(-math.expm1(-math.log(10)/(48000*x))*2**24) for x in d['piano_decay_s']]
        wire+=struct.pack('<BHH',d['piano_hold'][0]|d['piano_hold'][1]<<1,*coefficients)
    return d,wire

def select_payload(p):
    h=p.get('hand');valid=p.get('valid',True);z=p.get('zone',0)
    if type(h) is not int or h not in (0,1) or type(valid) is not bool or type(z) is not int or z not in range(12):raise ValueError('预选参数无效')
    return bytes([h,valid,z])

def strike_payload(p,event_id):
    if set(p)-{'hand','zone','profile','octave','velocity','capture','event_id'}:raise ValueError('未知击发参数')
    h=p.get('hand');profile=p.get('profile',0);z=p.get('zone');octave=p.get('octave',0);velocity=p.get('velocity',32);capture=p.get('capture',True)
    if type(h) is not int or h not in (0,1):raise ValueError('hand为0左手或1右手')
    notes=note_map(profile,z,octave,False)
    if type(velocity) is not int or not 1<=velocity<=127 or type(capture) is not bool:raise ValueError('力度为1～127，抓取为布尔值')
    if type(event_id) is not int or not 1<=event_id<=0xffffffff:raise ValueError('击发编号为1～4294967295')
    return struct.pack('<IBBBBBB',event_id,h,z,profile,octave&255,velocity,capture),notes

from lab_monitor import MonitorEngineMixin

class DuoEngineMixin(MonitorEngineMixin):
    def reset_duo(self):
        self.instrument_state={} 
        self.reset_monitor()
        from lab_expression import DEFAULT
        self.expression=[dict(DEFAULT),dict(DEFAULT)]
        self.channel_names=list(LEGACY_CHANNELS);self.audio_metadata={};self.capture_metadata={}
        self.duo_config=config_payload({})[0];self.duo_config['run']=False
        self.duo=dict(running=False,profiles=[0,0],presets=[0,0],selected=[None,None],hits=[0,0],
                      event_id=0,hand=0,velocity=0,active_mask=0,gates=0,owned=0,notes=[0]*32,envelopes=[0]*32,
                      capture_event_id=0,capture_skipped=0,capturing=False,stop_reason=0,revision=0)
        self.duo_revision=0;self.duo_next_event=1;self.duo_heartbeat_at=0;self.duo_heartbeat_ticket=None
        self.duo_sim_voices=[];self.duo_mock_gain=1.
    def enable_duo_capabilities(self):
        self.capabilities['instrument']=self.device.startswith('DUO04-LIVE ')
        if not self.capabilities['instrument']:self.capabilities.pop('timbre_names',None)
        expression=self.device.startswith(('DUO02-MOUSE 1.4','DUO04-LIVE ')) or '模拟' in self.device
        monitor=expression or self.device.startswith('DUO02-MOUSE 1.3') or '模拟' in self.device
        quality=monitor or self.device.startswith('DUO02-MOUSE 1.2') or '模拟' in self.device
        extended=quality or self.device.startswith('DUO02-MOUSE 1.1')
        self.capabilities.update(duo_mouse=True,duo_expression=expression,duo_monitor=monitor,voices=32,capture_sizes=[512,2048],fine_gain=False,piano=False,piano_control=False,
                                 envelope=False,imu=False,capture_channels=list(CHANNELS),duo_extended=extended,duo_gain_max=256 if extended else 64,duo_quality=quality,duo_presets=6 if quality else 4)
        if self.device.startswith('DUO04-LIVE '):self.capabilities.update(instrument=True,duo_expression=True,duo_monitor=True,duo_extended=True,duo_quality=True,duo_presets=4,duo_gain_max=256,capture_sizes=[512,2048],timbre_names=['钢琴','马林巴','电钢琴','拨弦'])
        self.channel_names=list(CHANNELS)
    def duo_snapshot(self):
        with self.lock:return dict(self.duo,instrument=dict(self.instrument_state),config=dict(self.duo_config),expression=[dict(h) for h in self.expression],source=self.source)
    def handle_duo_frame(self,f):
        if self.monitor_frame(f):return True
        if f.kind==DUO_META:
            if len(f.payload)!=16:raise ValueError('DUO采样元数据长度错误')
            cid,event,tick,revision,fmt,channels,_=struct.unpack('<HIIHBBH',f.payload)
            if fmt!=1 or channels!=5:raise ValueError('不支持的DUO采样格式')
            self.capture_metadata[cid]=dict(capture_id=cid,event_id=event,board_tick=tick,config_revision=revision,channels=list(CHANNELS))
            while len(self.capture_metadata)>16:self.capture_metadata.pop(next(iter(self.capture_metadata)))
            return True
        if f.kind!=DUO_STATUS:return False
        b=f.payload
        if (len(b),b[0]) not in ((180,1),(186,2),(192,3),(208,4),(224,5),(240,6)):raise ValueError('DUO状态格式错误')
        def u(offset):return struct.unpack_from('<I',b,offset)[0]
        self.enable_duo_capabilities()
        self.duo_config=dict(run=bool(b[1]),profiles=list(b[4:6]),presets=list(b[6:8]),chord=bool(b[8]),effect=b[9],wet=b[10],gain=b[11]+(256*(b[79]&1) if b[0]>=2 else 0))
        if b[0]>=2:self.duo_config.update(hold_ms=list(struct.unpack_from('<HH',b,180)),release_ids=[b[184]&3,(b[184]>>2)&3])
        if b[0]>=3:
            coef=struct.unpack_from('<HH',b,187)
            if any(x<27 or x>4025 for x in coef):raise ValueError('钢琴衰减系数无效')
            self.duo_config.update(piano_hold=[bool(b[186]&1),bool(b[186]&2)],piano_decay_s=[-math.log(10)/(48000*math.log1p(-x/2**24)) for x in coef])
        self.duo.update(running=bool(b[1]),config_busy=bool(b[2]),stop_reason=b[3],profiles=list(b[4:6]),presets=list(b[6:8]),
            selected=[(b[12+i]&15) if b[12+i]&128 else None for i in (0,1)],last_zones=list(b[14:16]),hits=[u(16),u(20)],
            event_id=u(24),hand=b[28],velocity=b[29],effect=b[30],actual_wet=b[31],active_mask=u(32),gates=u(36),
            stolen=u(40),underflows=u(44),clips=u(48),fx_drops=u(52),board_crc=u(56),event_drops=u(60),
            capture_event_id=u(64),capture_skipped=u(68),owned=u(72),capturing=bool(b[76]),actual_gain=b[77],
            revision=struct.unpack_from('<H',b,80)[0],notes=list(b[84:116]),envelopes=list(struct.unpack_from('<32H',b,116)))
        if b[0]>=2:self.duo.update(actual_gain=b[77]+256*((b[79]>>1)&1),amplifier_off=bool(b[185]))
        if b[0]>=4:
            self.monitor_ids=list(b[202:202+b[201]])
            amp=struct.unpack_from('<H',b,198)[0]
            self.sine_state=dict(mode=bool(b[192]),enabled=bool(b[193]),active=bool(b[206]),frequency_hz=u(194)*self.fs/2**32,
                level_dbfs=20*math.log10(amp/32767) if amp else None,channels={1:'left',2:'right',3:'both'}.get(b[200],'none'))
        if b[0]>=5:
            from lab_expression import decode_expression
            self.expression=decode_expression(b[208:224])
        if b[0]>=6:self.instrument_state=dict(mode=b[224],page=b[225],field=b[226],editing=bool(b[227]),lesson=b[228],position=b[229],target_hand=b[230],target_note=b[231],correct=struct.unpack_from('<H',b,232)[0],wrong=struct.unpack_from('<H',b,234)[0],online=b[236],octave_codes=[b[237]&3,(b[237]>>2)&3])
        self.clips=u(48);self.drops=u(52)+u(60);self.duo_revision+=1
        return True
    def duo_heartbeat(self):
        if not self.capabilities.get('duo_mouse') or not self.ready or not (self.duo.get('running') or self.sine_state.get('active')):return
        if time.monotonic()-self.duo_heartbeat_at<.5:return
        if self.duo_heartbeat_ticket is not None and self.command_result(self.duo_heartbeat_ticket)['state'] not in ('acknowledged','failed'):return
        self.duo_heartbeat_at=time.monotonic();self.duo_heartbeat_ticket=self.send(DUO_HEARTBEAT)
    def demo_duo(self):
        self.close();self.reset();self.stop.clear();self.ready=True;self.source='模拟演示（DUO02鼠标，非实测）';self.device='DUO02-MOUSE 模拟'
        self.enable_duo_capabilities();self.status='鼠标模拟已就绪，点击开始测试'
    def simulate_duo_command(self,kind,payload):
        if kind==60:
            field,value=struct.unpack('<BH',payload)
            if field==0:self.instrument_state['mode']=value;self.duo['running']=False;self.duo_config['run']=False
            elif field in (1,2):self.duo_config['presets'][field-1]=value
            elif field in (3,4):self.duo_config['profiles'][field-3]=value
            elif field in (5,6):self.instrument_state.setdefault('octave_codes',[2,2])[field-5]=value
            elif field==7:self.duo_config['chord']=bool(value)
            elif field==8:self.duo_config['gain']=value
            elif field==9:self.duo_config['effect']=value
            elif field==10:self.duo_config['wet']=value
            elif field in (11,12):self.duo_config.setdefault('hold_ms',[1500,1500])[field-11]=value
            elif field in (13,14):self.duo_config.setdefault('release_ids',[1,1])[field-13]=value
            elif field in (15,16):self.expression[field-15]['vibrato']=bool(value)
            elif field in (17,18):self.expression[field-17]['glide']=bool(value)
            elif field==19:self.instrument_state['lesson']=value
            elif field==20:self.instrument_state.update(mode=2,position=0,correct=0,wrong=0);self.duo_config['run']=True;self.duo['running']=True
            elif field==22:self.duo_config['run']=bool(value);self.duo['running']=bool(value)
            self.duo_revision+=1;return
        from lab_monitor import MONITOR_SELECT,SINE_START,SINE_STOP
        if kind==57:
            from lab_expression import decode_expression
            self.expression=decode_expression(payload)
        elif kind==MONITOR_SELECT:self.monitor_ids=list(payload[1:1+payload[0]])
        elif kind==SINE_START:
            _,word,amp,ch=struct.unpack('<BIHB',payload)
            self.sine_state=dict(mode=True,enabled=True,active=True,frequency_hz=word*self.fs/2**32,level_dbfs=20*math.log10(amp/32767),channels={1:'left',2:'right',3:'both'}[ch])
        elif kind==SINE_STOP:self.sine_state.update(mode=False,enabled=False,active=False)
        elif kind==DUO_CONFIG:
            self.sine_state.update(mode=False,enabled=False,active=False)
            self.duo_sim_voices=[];self.duo_config=dict(run=bool(payload[0]),profiles=list(payload[1:3]),presets=list(payload[3:5]),chord=bool(payload[5]),effect=payload[6],wet=payload[7],gain=payload[8])
            if len(payload)>=15:
                gain,left,right,release=struct.unpack_from('<HHHB',payload,8)
                self.duo_config.update(gain=gain,hold_ms=[left,right],release_ids=[release&3,(release>>2)&3])
            if len(payload)==20:
                hold,left,right=struct.unpack_from('<BHH',payload,15)
                self.duo_config.update(piano_hold=[bool(hold&1),bool(hold&2)],piano_decay_s=[-math.log(10)/(48000*math.log1p(-x/2**24)) for x in (left,right)])
            self.duo.update(running=bool(payload[0]),profiles=list(payload[1:3]),presets=list(payload[3:5]),revision=self.duo['revision']+1)
        elif kind==DUO_SELECT:
            self.duo['selected'][payload[0]]=payload[2] if payload[1] else None
        elif kind==DUO_STOP:
            self.sine_state.update(mode=False,enabled=False,active=False);self.duo['actual_gain']=0
            self.duo_config['run']=False;self.duo['running']=False;self.duo_sim_voices=[];self.duo['active_mask']=0;self.duo['gates']=0;self.duo['owned']=0;self.duo['envelopes']=[0]*32
        elif kind==DUO_STRIKE:
            eid,h,z,profile,octave,velocity,capture=struct.unpack('<IBBBBBB',payload);octave=octave if octave<128 else octave-256
            if not self.duo['running']:raise ValueError('先开始鼠标测试')
            if profile!=self.duo_config['profiles'][h]:raise ValueError('击发布局与已应用配置不符')
            midi=note_map(profile,z,octave,self.duo_config['chord'] and h==0)
            now=time.monotonic()
            for note in midi:self.duo_sim_voices.append(dict(note=note,hand=h,start=now,velocity=velocity,preset=self.duo_config['presets'][h],
                hold=self.duo_config.get('hold_ms',[60,60])[h]/1000,release=(.2,.5,1.5)[self.duo_config.get('release_ids',[1,1])[h]],
                piano_hold=self.duo_config.get('piano_hold',[False,False])[h],piano_decay=self.duo_config.get('piano_decay_s',[6.,6.])[h]))
            self.duo['hits'][h]+=1;self.duo.update(event_id=eid,hand=h,velocity=velocity,capture_event_id=eid if capture else self.duo['capture_event_id'])
            if capture:self.make_duo_audio(512,eid)
        elif kind==P.CAPTURE:self.make_duo_audio(struct.unpack_from('<H',payload,1)[0] if len(payload)==3 else 2048,0)
        self.duo_revision+=1
    def make_duo_audio(self,points=512,event_id=0):
        now=time.monotonic();t=np.arange(points)/self.fs;dry=np.zeros((points,2),float)
        self.duo_sim_voices=[v for v in self.duo_sim_voices if now-v['start']<v['hold']+v['release']]
        raw_voices=np.zeros((points,32),np.int16)
        self.duo['notes']=[0]*32;self.duo['envelopes']=[0]*32;mask=0;used=[0,0]
        for voice in self.duo_sim_voices:
            h=voice['hand'];index=h*16+used[h]%16;used[h]+=1
            age=max(.001,now-voice['start'])+t;f=440*2**((voice['note']-69)/12);phase=2*np.pi*f*age
            shape=np.sin(phase)+(.15 if voice['preset'] in (0,1) else .06)*np.sin(2*phase)
            if voice['preset']==4:shape=.625*np.sin(phase)+(.25+.75*np.exp(-age*6))*(.25*np.sin(2*phase)+.125*np.sin(3*phase)+.0625*np.sin(4*phase))
            elif voice['preset']==5:shape=np.sin(phase)
            decay=(np.ones_like(age) if voice['piano_hold'] else np.exp(-age*np.log(10)/voice['piano_decay'])) if voice['preset']==4 else (1 if voice['preset'] in (2,5) else np.exp(-age*5))
            env=np.minimum(1,age/.004)*decay*np.exp(-np.maximum(0,age-voice['hold'])*6.91/voice['release'])
            raw_voices[:,index]=np.clip(shape*env*voice['velocity']/127*32000,-32768,32767).astype(np.int16)
            dry[:,h]+=raw_voices[:,index].astype(float)/16
            mask|=1<<index;self.duo['notes'][index]=voice['note'];self.duo['envelopes'][index]=int(env[0]*65535)
        dry=np.clip(dry,-32768,32767).astype(np.int16)
        gain=self.duo_config['gain']/256 if self.duo['running'] else 0
        limited=dry.astype(float)
        if self.capabilities.get('duo_quality'):
            limited*=8
            for i,row in enumerate(limited):
                peak=max(abs(row));desired=min(1.,28000/max(1.,peak));self.duo_mock_gain=min(desired,self.duo_mock_gain+64/65536);limited[i]*=self.duo_mock_gain
        scaled=limited*gain;post=(np.sign(scaled)*np.floor(np.abs(scaled)+.5)).astype(np.int16)
        self.audio=np.column_stack((dry,post,((post[:,0].astype(int)+post[:,1].astype(int))//2))).astype(np.int16)
        ids=list(self.monitor_ids)
        if self.sine_state['enabled']:
            state=self.sine_state;wave=np.rint(np.sin(2*np.pi*state['frequency_hz']*(t+now))*32767*10**(state['level_dbfs']/20)).astype(np.int16)
            l=wave if state['channels'] in ('left','both') else np.zeros_like(wave);r=wave if state['channels'] in ('right','both') else np.zeros_like(wave)
            self.audio=np.column_stack((l,r,l,r,(l.astype(int)+r.astype(int))//2)).astype(np.int16);ids=[]
        self.voice_audio=raw_voices[:,ids]
        self.audio_revision+=1;self.audio_received_at=time.monotonic()
        self.audio_metadata=dict(capture_id=self.audio_revision&65535,event_id=event_id,board_tick=int(now*self.clock)&0xffffffff,
                                 config_revision=self.duo['revision'],channels=list(CHANNELS),simulated=True,monitor_voices=ids,calibration=bool(self.sine_state['enabled']),frequency_hz=self.sine_state['frequency_hz'],level_dbfs=self.sine_state['level_dbfs'],calibration_channels=self.sine_state['channels'])
        self.duo.update(active_mask=mask,gates=mask,owned=mask,capturing=False,actual_gain=self.duo_config['gain'] if self.duo['running'] else 0)
        self.remember_audio();self.status=f'模拟完整采样 {points} 点，击发 {event_id}（非实测）'

def execute_duo(controller,j,action,p):
    e=controller.engine
    if action=='duo.demo':e.demo_duo();return e.duo_snapshot()
    if not e.capabilities.get('duo_mouse'):raise ValueError('此功能需要重新下载DUO02-MOUSE测试固件；当前固件不支持')
    if not e.ready:raise ValueError('请先连接FPGA')
    if action=='duo.configure':
        p=dict(p);expression=p.pop('expression',None)
        if expression is not None:
            from lab_expression import execute_expression
            execute_expression(controller,j,expression)
        if e.sine_state.get('mode'):
            controller.ack(j,e.send(DUO_STOP));controller.wait(j,lambda:not e.sine_state.get('active'),3,'等待校准停止超时')
        if e.capabilities.get('instrument'):
            if any(x not in range(4) for x in p.get('presets',[0,0])):raise ValueError('DUO04音色编号0～3')
            if e.instrument_state.get('mode')!=1:
                from lab_instrument import execute as instrument_execute
                instrument_execute(controller,j,{'mode':1})
        cfg,wire=config_payload(p,e.capabilities.get('duo_extended',False),e.capabilities.get('duo_quality',False),e.capabilities.get('instrument',False));controller.ack(j,e.send(DUO_CONFIG,wire));e.duo_config=cfg
        return dict(config=cfg,accepted=True,source=e.source)
    if action=='duo.select':
        wire=select_payload(p);controller.ack(j,e.send(DUO_SELECT,wire));return dict(accepted=True,hand=wire[0],zone=wire[2] if wire[1] else None)
    if action=='duo.strike':
        event=p.get('event_id',e.duo_next_event);wire,midi=strike_payload(p,event)
        if not e.duo_config['run']:raise ValueError('先点击开始测试')
        if wire[6]!=e.duo_config['profiles'][wire[4]]:raise ValueError('布局尚未应用，请等待配置完成')
        e.duo_next_event=(event%0xffffffff)+1
        # A lost ACK is an unknown result; never retry a timed-out strike.
        controller.ack(j,e.send(DUO_STRIKE,wire))
        return dict(event_id=event,accepted=True,hand=wire[4],notes=note_map(wire[6],wire[5],p.get('octave',0),e.duo_config['chord'] and wire[4]==0),
                    capture_requested=bool(wire[9]),capture_complete=False,source=e.source)
    if action=='duo.stop':
        controller.ack(j,e.send(DUO_STOP));e.duo_config['run']=False;e.duo['running']=False
        return dict(stopped=True,source=e.source)
    raise ValueError('未知DUO命令')
