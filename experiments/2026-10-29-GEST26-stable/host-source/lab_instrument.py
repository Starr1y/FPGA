"""DUO04 local-menu/host shared parameter adapter. IDs are firmware-specific."""
import struct,time
PRESETS=['钢琴','马林巴','电钢琴','拨弦']
MODES=['脱机演奏','电脑鼠标调试','逐音教学']
FIELDS={'mode':(0,0,2),'left_timbre':(1,0,3),'right_timbre':(2,0,3),
 'left_scale':(3,0,2),'right_scale':(4,0,2),'left_octave_code':(5,0,3),'right_octave_code':(6,0,3),
 'chord':(7,0,1),'volume':(8,0,256),'effect':(9,0,3),'wet':(10,0,255),
 'left_hold_ms':(11,100,10000),'right_hold_ms':(12,100,10000),
 'left_release':(13,0,2),'right_release':(14,0,2),'left_vibrato':(15,0,1),'right_vibrato':(16,0,1),
 'left_glide':(17,0,1),'right_glide':(18,0,1),'lesson':(19,0,2),'lesson_start':(20,1,1),'left_gesture':(29,0,1),'right_gesture':(30,0,1),'left_pitch_invert':(31,0,1),'right_pitch_invert':(32,0,1),
 'calibrate':(21,1,1),'run':(22,0,1)}

def validate(params):
    if not params or set(params)-set(FIELDS):raise ValueError('脱机参数名称无效')
    out=[]
    for key,value in params.items():
        if isinstance(value,bool):value=int(value)
        field,lo,hi=FIELDS[key]
        if type(value) is not int or not lo<=value<=hi:raise ValueError(f'{key}范围{lo}～{hi}')
        out.append((field,value))
    return out

def execute(controller,job,params):
    e=controller.engine
    if not e.ready or not e.capabilities.get('instrument'):raise ValueError('需要DUO04-LIVE 2.0固件')
    edits=validate(params)
    if any(f>=29 for f,v in edits) and not e.capabilities.get('gesture_v24'):raise ValueError('需要GEST24固件')
    if any(f>=29 for f,v in edits) and e.duo.get('running'):raise ValueError('停止演奏后再修改手势')
    for field,value in edits:
        before=e.duo_revision
        controller.ack(job,e.send(60,struct.pack('<BH',field,value)))
        controller.wait(job,lambda:e.duo_revision>before and matches_readback(e,field,value),3,'参数已应答，但对应参数状态读回超时')
    if params.get('mode') in (0,2):
        from lab_mouse_mode import restore
        restore(controller,job)
    return dict(accepted=True,instrument=dict(e.instrument_state),config=dict(e.duo_config),source=e.source)

def matches_readback(e,field,value):
    """A different queued status is not proof that this edit was applied."""
    c=e.duo_config;s=e.instrument_state
    if field in (29,30):return s.get('gesture',{}).get('enabled',[None,None])[field-29]==bool(value)
    if field in (31,32):return s.get('gesture',{}).get('invert',[None,None])[field-31]==bool(value)
    if field==0:return s.get('mode')==value
    for lo,hi,key in ((1,2,'presets'),(3,4,'profiles'),(11,12,'hold_ms'),(13,14,'release_ids')):
        if lo<=field<=hi:return c.get(key,[None,None])[field-lo]==value
    if field in (5,6):return s.get('octave_codes',[None,None])[field-5]==value
    for f,key in ((7,'chord'),(8,'gain'),(9,'effect'),(10,'wet'),(22,'run')):
        if field==f:return c.get(key)==value
    if field in (15,16):return e.expression[field-15]['vibrato']==bool(value)
    if field in (17,18):return e.expression[field-17]['glide']==bool(value)
    if field==19:return s.get('lesson')==value
    if field==20:return s.get('mode')==2 and c.get('run')
    # Calibration ACK confirms a request only; sensor completion is asynchronous.
    return field==21

def build_controls(gui,layout):
    from PySide6 import QtWidgets as W
    group=W.QGroupBox('DUO04 脱机菜单与教学（旧固件不可用）');row=W.QHBoxLayout(group)
    gui.instrument_mode=W.QComboBox();gui.instrument_mode.addItems(MODES);row.addWidget(gui.instrument_mode)
    def send(values):return gui.safe(lambda:gui.submit_command('instrument.set',values))
    button=W.QPushButton('切换模式并静音');button.clicked.connect(lambda:send({'mode':gui.instrument_mode.currentIndex()}));row.addWidget(button)
    start=W.QPushButton('开始 / 恢复')
    start.clicked.connect(lambda:gui.safe(lambda:gui.apply_duo(True)) if gui.engine.instrument_state.get('mode')==1 else send({'run':True}));row.addWidget(start)
    gui.instrument_song=W.QComboBox();gui.instrument_song.addItems(['左手音阶','右手音阶','双手交替']);row.addWidget(gui.instrument_song)
    teach=W.QPushButton('开始逐音教学');teach.clicked.connect(lambda:send({'lesson':gui.instrument_song.currentIndex(),'lesson_start':True}));row.addWidget(teach)
    zero=W.QPushButton('双手重新归中');zero.clicked.connect(lambda:send({'calibrate':True}));row.addWidget(zero)
    layout.addWidget(group);gui.instrument_group=group
    from lab_interaction import build_controls as build_interaction
    build_interaction(gui,layout)
    gui.instrument_feedback=W.QLabel('尚未连接脱机固件');gui.instrument_feedback.setWordWrap(True);layout.addWidget(gui.instrument_feedback)

def refresh_controls(gui):
    from PySide6 import QtCore as C
    from lab_interaction import refresh_controls as refresh_interaction
    refresh_interaction(gui)
    e=gui.engine;available=e.ready and e.capabilities.get('instrument',False)
    gui.instrument_group.setEnabled(available)
    if not available:return
    state=e.instrument_state;mode=state.get('mode',0)
    if not gui.duo_config_dirty and getattr(gui,'instrument_seen_revision',None)!=(e.audio_session,bool(e.duo_revision),e.duo.get('revision',0)):
        cfg=e.duo_config
        for widgets,key,scale in [(gui.duo_presets,'presets',1),(gui.duo_profiles,'profiles',1),(gui.duo_holds,'hold_ms',.001),(gui.duo_releases,'release_ids',1)]:
            for widget,value in zip(widgets,cfg.get(key,[])):
                with C.QSignalBlocker(widget):
                    if hasattr(widget,'setCurrentIndex'):widget.setCurrentIndex(value)
                    else:widget.setValue(value*scale)
        with C.QSignalBlocker(gui.duo_volume):gui.duo_volume.setValue(cfg['gain'])
        for h,code in enumerate(state.get('octave_codes',[0,0])):
            with C.QSignalBlocker(gui.duo_octaves[h]):gui.duo_octaves[h].setCurrentIndex((2,3,0,1)[code])
        for widget,key in ((gui.duo_chord,'chord'),(gui.duo_effect,'effect'),(gui.duo_wet,'wet')):
            with C.QSignalBlocker(widget):
                if hasattr(widget,'setChecked'):widget.setChecked(bool(cfg[key]))
                elif hasattr(widget,'setCurrentIndex'):widget.setCurrentIndex(cfg[key])
                else:widget.setValue(cfg[key])
        for h,fan in enumerate(gui.duo_fans):
            if fan.profile!=cfg['profiles'][h]:fan.profile=cfg['profiles'][h];fan.hover=None;fan.confirmed=None;fan.update()
        for h,widgets in enumerate(gui.duo_expression):
            for widget,key in zip(widgets,('vibrato','vibrato_hz','vibrato_cents','glide','glide_ms')):
                with C.QSignalBlocker(widget):
                    if hasattr(widget,'setChecked'):widget.setChecked(bool(e.expression[h][key]))
                    else:widget.setValue(e.expression[h][key])
        for h in (0,1):
            with C.QSignalBlocker(gui.duo_piano_holds[h]):gui.duo_piano_holds[h].setChecked(cfg.get('piano_hold',[False,False])[h])
            with C.QSignalBlocker(gui.duo_piano_decays[h]):gui.duo_piano_decays[h].setValue(cfg.get('piano_decay_s',[6.,6.])[h])
        gui.instrument_seen_revision=(e.audio_session,bool(e.duo_revision),e.duo.get('revision',0))
    if not gui.instrument_mode.hasFocus():
        with C.QSignalBlocker(gui.instrument_mode):gui.instrument_mode.setCurrentIndex(mode)
    gui.instrument_feedback.setText(f"板上模式：{MODES[min(mode,2)]}；传感器在线：{state.get('online',0):02b}；"
        f"教学进度：{state.get('position',0)}/16；目标：{'右手' if state.get('target_hand') else '左手'} MIDI {state.get('target_note',60)}；"
        f"正确 {state.get('correct',0)} / 错击 {state.get('wrong',0)}。保持时间到点松键，自然衰减与释音另计。")


def read_value(e,f):
    c=e.duo_config;s=e.instrument_state
    if f in (29,30):return int(s.get('gesture',{}).get('enabled',[True,True])[f-29])
    if f in (31,32):return int(s.get('gesture',{}).get('invert',[False,False])[f-31])
    if f==0:return s.get('mode',0)
    for lo,hi,key in ((1,2,'presets'),(3,4,'profiles'),(11,12,'hold_ms'),(13,14,'release_ids')):
        if lo<=f<=hi:return c[key][f-lo]
    if f in (5,6):return s.get('octave_codes',[0,0])[f-5]
    if f==19:return s.get('lesson',0)
    if f==23:return s.get('lesson_source',0)
    for k,v in ((7,'chord'),(8,'gain'),(9,'effect'),(10,'wet'),(22,'run')):
        if f==k:return int(c[v])
    return 0
