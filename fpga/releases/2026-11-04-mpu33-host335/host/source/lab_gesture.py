"""GEST24 capability and board-owned wrist expression. Simulation is explicit."""
import struct,time,math

def decode(b):
    if len(b)!=32:raise ValueError('手势状态长度错误')
    bends=struct.unpack_from('<hh',b,6);serials=struct.unpack_from('<HH',b,10);pitch=struct.unpack_from('<hh',b,14)
    return dict(enabled=[bool(b[0]&(1<<h)) for h in (0,1)],invert=[bool(b[1]&(1<<h)) for h in (0,1)],
        pressed=[bool(b[2]&(1<<h)) for h in (0,1)],fresh=[bool(b[3]&(1<<h)) for h in (0,1)],
        octave_codes=[b[4]&3,(b[4]>>2)&3],snapshot_codes=[b[5]&3,(b[5]>>2)&3],
        bend_cents=list(bends),group_serial=list(serials),pitch_degrees=[x/16 for x in pitch],board_tick=struct.unpack_from('<I',b,18)[0])

def encode(s):
    b=bytearray(32)
    for n,key in enumerate(('enabled','invert','pressed','fresh')):b[n]=sum(int(v)<<h for h,v in enumerate(s.get(key,[False,False])))
    for n,key in ((4,'octave_codes'),(5,'snapshot_codes')):
        values=s.get(key,[0,0]);b[n]=values[0]|values[1]<<2
    struct.pack_into('<hhHHhhI',b,6,*s.get('bend_cents',[0,0]),*[x&65535 for x in s.get('group_serial',[0,0])],*[round(x*16) for x in s.get('pitch_degrees',[0,0])],s.get('board_tick',0)&0xffffffff)
    return bytes(b)

def payload(action,p):
    if action=='gesture.configure':
        if set(p)-{'enabled','invert'}:raise ValueError('未知手势设置')
        enabled=p.get('enabled',[True,True]);invert=p.get('invert',[False,False])
        for x in (enabled,invert):
            if not isinstance(x,list) or len(x)!=2 or any(type(v) is not bool for v in x):raise ValueError('enabled/invert须为左右两个布尔值')
        return 64,bytes([sum(int(v)<<h for h,v in enumerate(enabled)),sum(int(v)<<h for h,v in enumerate(invert))])
    if action=='gesture.test':
        if set(p)-{'hand','pressed','pitch_degrees'}:raise ValueError('未知手势测试参数')
        h=p.get('hand');pressed=p.get('pressed',False);pitch=p.get('pitch_degrees',0)
        if type(h) is not int or h not in (0,1) or type(pressed) is not bool or type(pitch) not in (int,float) or not math.isfinite(pitch) or not -90<=pitch<=90:raise ValueError('hand为0/1，pressed为布尔值，俯仰为−90～90°')
        return 65,struct.pack('<BBh',h,pressed,round(pitch*16))
    raise ValueError('未知手势命令')

def execute(controller,j,action,p):
    e=controller.engine
    if not e.ready or not e.capabilities.get('gesture_v24'):raise ValueError('需要重新烧录 GEST24 固件；旧固件保留原功能')
    kind,wire=payload(action,p)
    if kind==64 and e.duo.get('running'):raise ValueError('请先停止演奏，再修改手势开关或方向')
    if kind==65 and e.instrument_state.get('mode')!=1:raise ValueError('虚拟手腕只在电脑调试模式有效')
    before=e.duo_revision
    controller.ack(j,e.send(kind,wire))
    if kind==64:
        controller.wait(j,lambda:e.duo_revision>before and e.instrument_state.get('gesture',{}).get('enabled')==[bool(wire[0]&1),bool(wire[0]&2)] and e.instrument_state.get('gesture',{}).get('invert')==[bool(wire[1]&1),bool(wire[1]&2)],3,'配置已应答但板上读回超时')
    return dict(accepted=True,source=e.source,gesture=e.instrument_state.get('gesture',{}),note='姿态输入已接受；按键消抖及音高变化见后续板上状态，非采样完成')

def simulate(e,kind,b):
    s=e.instrument_state.setdefault('gesture',dict(enabled=[True,True],invert=[False,False],pressed=[False,False],fresh=[False,False],octave_codes=[0,0],snapshot_codes=[0,0],bend_cents=[0,0],group_serial=[0,0],pitch_degrees=[0,0]))
    if kind==64:s['enabled']=[bool(b[0]&(1<<h)) for h in (0,1)];s['invert']=[bool(b[1]&(1<<h)) for h in (0,1)]
    else:
        h,pressed,q=struct.unpack('<BBh',b);pitch=q/16
        old=s['pressed'][h];s['pressed'][h]=bool(pressed);s['pitch_degrees'][h]=pitch;s['fresh'][h]=True
        if pressed and not old:
            s.setdefault('_reference',[0.,0.])[h]=pitch
            s.setdefault('_zone_reference',[0,0])[h]=e.duo.get('selected',[0,0])[h] or 0
        if pressed:
            from lab_duo import PROFILES
            profile=e.duo_config['profiles'][h];zone=e.duo.get('selected',[None,None])[h]
            reference=s.get('_zone_reference',[0,0])[h]
            shift=0 if zone is None else (PROFILES[profile][zone]-PROFILES[profile][min(reference,len(PROFILES[profile])-1)])*100
            s['bend_cents'][h]=round(max(-2400,min(2400,shift+max(-1200,min(1200,(pitch-s.get('_reference',[0,0])[h])*40)))))
        else:s['octave_codes'][h]=2 if pitch< -30 else 3 if pitch< -10 else 0 if pitch<20 else 1
        s['snapshot_codes'][h]=s['octave_codes'][h]
        voices=[v for v in e.duo_sim_voices if v['hand']==h]
        if voices:
            last=voices[-1]['group_id'];targets=[v for v in voices if v['group_id']==last]
            low=min(v['note'] for v in targets);high=max(v['note'] for v in targets)
            for v in targets:
                if pressed:
                    v['bend_cents']=max((36-low)*100,min((96-high)*100,s['bend_cents'][h]))
                    v['hold']=max(v['hold'],time.monotonic()-v['start']+.05);v['_held']=True
                elif v.pop('_held',False):v['hold']=max(0,time.monotonic()-v['start'])
    e.duo_revision+=1

def build_controls(gui,layout):
    from PySide6 import QtWidgets as W,QtCore as C
    box=W.QGroupBox('手腕表情：最近击发组／俯仰四档（GEST24固件）');grid=W.QGridLayout(box)
    gui.gesture_group=box;gui.gesture_widgets=[];gui.gesture_jobs={}
    for h,name in enumerate(('左手','右手')):
        enabled=W.QCheckBox(name+'手势');enabled.setChecked(True);inv=W.QCheckBox('俯仰反向')
        held=W.QPushButton('按住表情键');held.setCheckable(True);held.setToolTip('电脑测试中按住延长最新音，松开释音；自然衰减仍保留。需要先击发。')
        pitch=W.QDoubleSpinBox();pitch.setRange(-90,90);pitch.setDecimals(1);pitch.setSuffix('°');pitch.setSingleStep(.5)
        pitch.setToolTip('虚拟相对俯仰；先松键选八度，击发后按住并改变俯仰；仅电脑来源有效。')
        state=W.QLabel('未连接支持的固件');state.setWordWrap(True)
        gui.gesture_widgets.append((enabled,inv,held,pitch,state))
        for c,w in enumerate((enabled,inv,held,pitch,state)):grid.addWidget(w,h,c)
    apply=W.QPushButton('停止后应用左右手设置');grid.addWidget(apply,2,0,1,4)
    def configure():
        gui.safe(lambda:gui.submit_command('gesture.configure',dict(enabled=[w[0].isChecked() for w in gui.gesture_widgets],invert=[w[1].isChecked() for w in gui.gesture_widgets])))
    apply.clicked.connect(configure)
    note=W.QLabel('抬腕升高；±30°弯音±12半音；跨区不断奏。虚拟姿态超时40ms释放，恢复须先松键。真实按键请接J13.25/26和GND。');note.setWordWrap(True);grid.addWidget(note,3,0,1,5)
    layout.addWidget(box)
    timer=C.QTimer(gui);timer.setInterval(20)
    def tick():
        e=gui.engine
        if not e.ready or not e.capabilities.get('gesture_v24') or e.instrument_state.get('mode')!=1 or not any(e.instrument_state.get('gesture',{}).get('enabled',[False,False])):return
        for h,(_,_,held,pitch,_) in enumerate(gui.gesture_widgets):
            old=gui.gesture_jobs.get(h)
            if old:
                job=gui.controller.jobs.get(old)
                if job and job['state'] not in ('completed','failed','cancelled'):continue
            try:gui.gesture_jobs[h]=gui.submit_command('gesture.test',dict(hand=h,pressed=held.isChecked() and C.QCoreApplication.instance().applicationState()==C.Qt.ApplicationState.ApplicationActive,pitch_degrees=pitch.value()))['id']
            except Exception:pass
    timer.timeout.connect(tick);timer.start();gui.gesture_timer=timer

def refresh_controls(gui):
    if not hasattr(gui,'gesture_group'):return
    e=gui.engine;ok=e.ready and e.capabilities.get('gesture_v24',False);gui.gesture_group.setEnabled(ok)
    s=e.instrument_state.get('gesture',{})
    for h,(_,_,held,pitch,label) in enumerate(gui.gesture_widgets):
        held.setEnabled(ok and e.instrument_state.get('mode')==1);pitch.setEnabled(held.isEnabled())
        if not ok:label.setText('此固件不支持手腕手势');continue
        label.setText(f"板上：C{[4,5,2,3][s.get('octave_codes',[0,0])[h]]}，{'按住' if s.get('pressed',[False,False])[h] else '松开'}，弯音{s.get('bend_cents',[0,0])[h]}音分；组{s.get('group_serial',[0,0])[h]}；{'新鲜' if s.get('fresh',[False,False])[h] else '等待姿态'}")
