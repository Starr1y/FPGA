"""DUO04 2.1 semantic UI / lesson interface. Board owns all judging and state."""
import struct,time
ACTIONS={'rotate_left':0,'rotate_right':1,'confirm':2,'back':3,'key0':4,'key0_long':5,
         'key1':6,'key2':7,'key2_long':8,'menu':9,'diagnostic':10,'stop':11}
CONTROL={'stop':0,'start':1,'pause':2,'resume':3,'restart':4}
GROUPS=['左手','右手','音效','表达','教学','系统']
GROUP_FIELDS=[[1,3,5,11,13],[2,4,6,12,14],[9,10],[7,15,16,17,18],[19,23,27],[0,8,21,28]]

def payload(action,p):
    if action=='ui.action':
        if set(p)!={'action'} or p['action'] not in ACTIONS:raise ValueError('无效界面操作，使用 rotate_left/right、confirm、back、key0/1/2、menu、diagnostic、stop')
        return 61,bytes([ACTIONS[p['action']]])
    if action=='lesson.configure':
        if set(p)-{'source','lesson'}:raise ValueError('未知教学配置项')
        source=p.get('source','imu');song=p.get('lesson',0)
        if source not in ('imu','mouse') or type(song) is not int or song not in range(3):raise ValueError('来源为 imu/mouse，练习编号为0～2')
        return 62,bytes([source=='mouse',song])
    if action=='lesson.control':
        if set(p)!={'action'} or p['action'] not in CONTROL:raise ValueError('教学动作使用 start/pause/resume/stop/restart')
        return 63,bytes([CONTROL[p['action']]])
    raise ValueError('未知交互命令')

def execute(controller,j,action,p):
    e=controller.engine
    if not e.ready or not e.capabilities.get('interaction_v21'):raise ValueError('此功能需要 DUO04-LIVE 2.1 新固件；旧2.0位流不可用')
    kind,wire=payload(action,p);before=e.duo_revision;config_revision=e.duo.get('revision',0);serial=e.instrument_state.get('ui_serial',0)
    controller.ack(j,e.send(kind,wire))
    def applied():
        s=e.instrument_state
        if e.duo_revision<=before:return False
        if kind==61:return s.get('ui_serial',0)!=serial
        if e.duo.get('revision',0)==config_revision:return False
        if kind==62:return s.get('lesson_source')==wire[0] and s.get('lesson')==wire[1] and not e.duo['running']
        if wire[0] in (0,2):return not e.duo['running']
        return s.get('mode')==2 and (e.duo['running'] or e.duo.get('stop_reason')==5)
    controller.wait(j,applied,3,'命令已应答，但对应界面／教学状态读回超时；没有自动重发')
    return dict(accepted=True,instrument=dict(e.instrument_state),config=dict(e.duo_config),source=e.source,
                note='设备状态已读回；听音及实际显示需人工确认')

def build_controls(gui,layout):
    from PySide6 import QtWidgets as W
    group=W.QGroupBox('2.1 板上按键、编码器与教学（状态由 FPGA 读回）');box=W.QVBoxLayout(group)
    def send(action,p):return gui.safe(lambda:gui.submit_command(action,p))
    row=W.QHBoxLayout()
    for title,action,tip in [('旋钮 −','rotate_left','主画面减音量；菜单上一项或减少'),('旋钮 ＋','rotate_right','主画面加音量；菜单下一项或增加'),
       ('按下／确认','confirm','主画面打开快捷菜单，再按才执行；编辑中确认'),('长按／返回','back','返回一级，不额外触发短按'),
       ('KEY0','key0','主画面归中当前手，菜单中确认'),('KEY1','key1','主画面轮换当前手四音色，菜单中下一项或增加'),
       ('KEY2','key2','主画面切换操作手，菜单中上一项或减少')]:
        b=W.QPushButton(title);b.setToolTip(tip);b.clicked.connect(lambda checked=False,a=action:send('ui.action',{'action':a}));row.addWidget(b)
    box.addLayout(row);row=W.QHBoxLayout()
    for title,action in [('K0长按 换区','key0_long'),('K2长按 设置','key2_long'),('设置菜单','menu'),('诊断／演奏','diagnostic'),('停止 K0＋K2','stop')]:
        b=W.QPushButton(title);b.clicked.connect(lambda checked=False,a=action:send('ui.action',{'action':a}));row.addWidget(b)
    box.addLayout(row);row=W.QHBoxLayout()
    gui.lesson_source=W.QComboBox();gui.lesson_source.addItems(['IMU 脱机教学','鼠标教学测试']);row.addWidget(gui.lesson_source)
    gui.lesson_song=W.QComboBox();gui.lesson_song.addItems(['左手七音','右手七音','双手交替']);row.addWidget(gui.lesson_song)
    gui.lesson_draft=False;gui.lesson_config_job=None
    gui.lesson_source.currentIndexChanged.connect(lambda *_:setattr(gui,'lesson_draft',True));gui.lesson_song.currentIndexChanged.connect(lambda *_:setattr(gui,'lesson_draft',True))
    def configure_lesson():
        def submit():
            j=gui.submit_command('lesson.configure',{'source':('imu','mouse')[gui.lesson_source.currentIndex()],'lesson':gui.lesson_song.currentIndex()});gui.lesson_config_job=j['id']
        gui.safe(submit)
    b=W.QPushButton('应用练习与来源（先停止）');b.clicked.connect(configure_lesson);row.addWidget(b)
    for title,a in [('开始','start'),('暂停','pause'),('继续','resume'),('停止','stop'),('重新开始','restart')]:
        b=W.QPushButton(title);b.clicked.connect(lambda checked=False,a=a:send('lesson.control',{'action':a}));row.addWidget(b)
    box.addLayout(row)
    gui.interaction_status=W.QLabel('2.1新增功能：先应用教学来源与练习，再开始；鼠标模式点击下方音区。');gui.interaction_status.setWordWrap(True);box.addWidget(gui.interaction_status)
    layout.addWidget(group);gui.interaction_group=group

def refresh_controls(gui):
    e=gui.engine;s=e.instrument_state
    enabled=e.ready and e.capabilities.get('interaction_v21',False);gui.interaction_group.setEnabled(enabled)
    if not enabled:
        gui.interaction_status.setText('需重新编译并烧录 DUO04-LIVE 2.1；旧固件仍保留原功能。');return
    if e.source.startswith('模拟'):simulation_tick(e)
    job=getattr(gui,'lesson_config_job',None)
    if job and gui.controller.job(job)['state'] in ('completed','failed','cancelled'):
        gui.lesson_config_job=None;gui.lesson_draft=False
    if not getattr(gui,'lesson_draft',False):
        from PySide6 import QtCore as C
        with C.QSignalBlocker(gui.lesson_source):gui.lesson_source.setCurrentIndex(s.get('lesson_source',0))
        with C.QSignalBlocker(gui.lesson_song):gui.lesson_song.setCurrentIndex(s.get('lesson',0))

    groups=GROUPS;level=s.get('menu_level',0);grp=s.get('menu_group',0)
    cal=['尚未请求','等待归中','归中完成','归中失败'][min(3,s.get('calibration',0))]
    gui.interaction_status.setText(f"板上页面：{['演奏','菜单','教学','诊断'][min(3,s.get('page',0))]}；操作手：{'右' if s.get('active_hand') else '左'}；"
        f"菜单：{['关闭','快捷','分组','选项','编辑','确认'][min(5,level)]}／{groups[min(5,grp)]}／第{s.get('menu_item',0)+1}项；{cal}\n"
        f"教学来源：{'鼠标测试' if s.get('lesson_source') else '真实IMU'}；{s.get('position',0)}/16；"
        f"目标 {'右' if s.get('target_hand') else '左'}手音区 {s.get('target_zone',0)+1}，MIDI {s.get('target_note',60)}；"
        f"正确 {s.get('correct',0)}／错击 {s.get('wrong',0)}；{'已完成，需重新开始' if s.get('finished') else '进行中' if e.duo['running'] else '已暂停／停止'}。"
        +(' 教学中禁止修改音阶、八度和和弦。' if s.get('mode')==2 else ''))
    for hand,fan in enumerate(getattr(gui,'duo_fans',[])):
        fan.lesson_target=s.get('target_zone') if s.get('mode')==2 and not s.get('finished') and s.get('target_hand')==hand else None
        fan.lesson_feedback=s.get('feedback',0) if s.get('feedback_hand')==hand else 0
        fan.lesson_feedback_zone=s.get('feedback_zone');fan.update()

def target(s):
    n=s.get('position',0);degree=n if n<8 else 15-n;zone=0 if degree==7 or n>=16 else degree
    s['target_zone']=zone;s['target_note']=[60,62,64,65,67,69,71][zone]
    s['target_hand']=0 if s.get('lesson',0)==0 else 1 if s.get('lesson')==1 else n%2
    s['finished']=n>=16

def simulation_tick(e):
    s=e.instrument_state
    if s.get('feedback') and e.duo['running'] and time.monotonic()>=s.get('_feedback_until',float('inf')):
        if s['feedback']==1:s['position']=s.get('position',0)+1
        s['feedback']=0;target(s);e.duo_revision+=1

def simulation_hit(e,h,z,n):
    s=e.instrument_state;simulation_tick(e)
    if s.get('mode')!=2 or not s.get('lesson_source') or s.get('finished') or s.get('feedback')==1:return
    good=h==s['target_hand'] and n==s['target_note'];s['feedback']=1 if good else 2
    key='correct' if good else 'wrong';s[key]=s.get(key,0)+1
    s.update(feedback_hand=h,feedback_zone=z,_feedback_until=time.monotonic()+(.25 if good else .18))
    s['lesson_serial']=(s.get('lesson_serial',0)+1)%65536

def simulate(e,kind,data):
    s=e.instrument_state;target(s)
    def stop():e.duo.update(running=False);e.duo_config['run']=False;e.duo_sim_voices=[]
    def start():
        if s.get('mode')!=2:s['_saved']=(list(e.duo_config['profiles']),list(s.get('octave_codes',[0,0])),e.duo_config['chord'])
        s.update(mode=2,position=0,correct=0,wrong=0,feedback=0,finished=False,octave_codes=[0,0]);e.duo_config.update(profiles=[0,0],chord=False,run=True);e.duo['running']=True;target(s)
    if kind==62:
        if s.get('mode')!=2:s['_saved']=(list(e.duo_config['profiles']),list(s.get('octave_codes',[0,0])),e.duo_config['chord'])
        stop();s.update(mode=2,octave_codes=[0,0],lesson_source=data[0],lesson=data[1],position=0,correct=0,wrong=0,feedback=0);e.duo_config.update(profiles=[0,0],chord=False);target(s)
    elif kind==63:
        action=data[0]
        if action in (0,2):
            if s.get('feedback') and action==2:s['_feedback_remaining']=max(0,s['_feedback_until']-time.monotonic())
            stop()
            if action==0:
                if s.get('feedback')==1:s['position']=s.get('position',0)+1;target(s)
                s['feedback']=0
        elif action in (1,4):start()
        elif not s.get('finished'):
            e.duo['running']=True;e.duo_config['run']=True
            if '_feedback_remaining' in s:s['_feedback_until']=time.monotonic()+s.pop('_feedback_remaining')
    elif kind==61:
        a=data[0];level=s.get('menu_level',0);item=s.get('menu_item',0);g=s.get('menu_group',0);hand=s.get('active_hand',0)
        if a==11:stop();s.update(menu_level=0,feedback=0);e.duo['stop_reason']=3
        elif a==9:s['menu_level']=0 if level else 2;s['menu_item']=0
        elif a==10:s['page']=0 if s.get('page')==3 else 3;s['menu_level']=0
        elif a==3 or (level and a==5):s['menu_level']={5:3,4:3,3:2}.get(level,0)
        elif not level:
            if a in (0,1):e.duo_config['gain']=max(0,min(256,e.duo_config['gain']+(4 if a else -4)))
            elif a==2:s.update(menu_level=1,menu_item=0)
            elif a==4:s['calibration']=3
            elif a==5 and s.get('mode')!=2:e.duo_config['profiles'][hand]=(e.duo_config['profiles'][hand]+1)%3
            elif a==6:e.duo_config['presets'][hand]=(e.duo_config['presets'][hand]+1)%4
            elif a==7:s['active_hand']=1-hand
            elif a==8:s.update(menu_level=3,menu_group=hand,menu_item=0,field=1+hand)
        elif a in (0,1,6,7):
            if level in (1,2,3):
                s['menu_item']=(item+(1 if a in (1,6) else -1))%({1:5,2:6}.get(level,len(GROUP_FIELDS[g])))
                if level==3:s['field']=GROUP_FIELDS[g][s['menu_item']]
            elif level==4:
                from lab_instrument import FIELDS
                f=s.get('field',0);key=next((k for k,v in FIELDS.items() if v[0]==f),None)
                if key:
                    from lab_instrument import read_value
                    v=read_value(e,f);lo,hi=FIELDS[key][1:];step=100 if f in (11,12) else 4 if f==8 else 8 if f==10 else 1
                    e.simulate_duo_command(60,struct.pack('<BH',f,max(lo,min(hi,v+(step if a in (1,6) else -step)))))
        elif a in (2,4):
            if level==1:
                if item==0:
                    if s.get('mode')==2 and s.get('finished'):start()
                    else:e.duo['running']=not e.duo['running'];e.duo_config['run']=e.duo['running']
                    s['menu_level']=0
                elif item==1:
                    if s.get('mode')==2:
                        s['mode']=0
                        if '_saved' in s:e.duo_config['profiles'],s['octave_codes'],e.duo_config['chord']=s.pop('_saved')
                    else:s['_saved']=(list(e.duo_config['profiles']),s.get('octave_codes',[0,0]),e.duo_config['chord']);s['mode']=2;e.duo_config.update(profiles=[0,0],chord=False);s['octave_codes']=[0,0]
                    stop();s['menu_level']=0
                elif item==2:s.update(menu_level=3,menu_group=hand,menu_item=0,field=hand+1)
                elif item==3:s.update(menu_level=2,menu_item=0)
                else:s.update(menu_level=0,page=3)
            elif level==2:s.update(menu_level=3,menu_group=item,menu_item=0,field=GROUP_FIELDS[item][0])
            elif level==3:s['menu_level']=5 if s.get('field') in (21,27,28) else 4
            elif level in (4,5):
                if level==5 and s.get('field')==27:start()
                s['menu_level']=3
        s['ui_serial']=(s.get('ui_serial',0)+1)%65536
    if s.get('menu_level'):s['page']=1
    elif s.get('page')!=3:s['page']=2 if s.get('mode')==2 else 0
    if kind in (62,63):e.duo['revision']=(e.duo.get('revision',0)+1)%65536
    e.duo_revision+=1
