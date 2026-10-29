"""GEST25/26 versioned hardware diagnostics. Missing telemetry is never zero-filled."""
import struct,time
from collections import deque
FAILURES={3:'I²C报文错误',0:'无',1:'未启动',2:'链路错误',4:'报告格式错误',5:'配置未齐',6:'姿态超时',7:'加速度超时',9:'角速度超时',10:'看门狗超时'}
def decode(payload):
    if len(payload)!=192:raise ValueError('IMU诊断长度错误')
    result=[]
    for h in (0,1):
        b=payload[h*96:(h+1)*96];flags=struct.unpack_from('<I',b)[0]
        age=[x/50000 for x in struct.unpack_from('<4I',b,42)]
        result.append(dict(online=bool(flags&1),calibrated=bool(flags&2),calibrating=bool(flags&4),armed=bool(flags&8),playable=bool(flags&16),out_of_range=bool(flags&32),drift=bool(flags&64),fresh=bool(flags&128),accuracy=(flags>>8)&3,calibration_state=(flags>>10)&3,progress=(flags>>12)&63,zone=(flags>>18)&15,hit_zone=(flags>>22)&15,profile=(flags>>26)&3,trigger=(flags>>28)&3,fault=bool(flags>>31),
            yaw=struct.unpack_from('<h',b,4)[0]/16,pitch=struct.unpack_from('<h',b,6)[0]/16,roll=struct.unpack_from('<h',b,8)[0]/16,
            hits=struct.unpack_from('<I',b,16)[0],protocol_errors=struct.unpack_from('<I',b,24)[0],rates=list(struct.unpack_from('<3H',b,32)),overruns=struct.unpack_from('<I',b,38)[0],ages_ms=age,linear_z=struct.unpack_from('<h',b,58)[0]/256,
            sequence_gaps=struct.unpack_from('<I',b,60)[0],resets=struct.unpack_from('<I',b,64)[0],first_failure=b[68],last_failure=b[69],header=struct.unpack_from('<H',b,70)[0],inputs=b[72],features=b[73]))
        if b[74]==2:
            result[-1].update(extension=2,snapshot_valid=bool(b[75]&1),yaw_invert=bool(b[75]&2),linear_hz=struct.unpack_from('<H',b,76)[0],linear_interval_ms=struct.unpack_from('<I',b,78)[0]/10,
                snapshot_zone=b[82]&15,snapshot_octave=(b[82]>>4)&3,snapshot_profile=b[82]>>6,zone_candidate=b[83]&15,snapshot_sensor_tick=struct.unpack_from('<I',b,84)[0],hit_sensor_tick=struct.unpack_from('<I',b,88)[0],filtered_yaw=struct.unpack_from('<h',b,92)[0]/16,snapshot_blocked=bool(b[94]))
    return result
def reason(d):
    if d['fault']:return '总线／初始化故障：'+FAILURES.get(d['last_failure'],str(d['last_failure']))
    if not d['online']:return '报告未齐或超时：'+FAILURES.get(d['last_failure'],'待检查')
    if d['calibrating']:return '归中中'
    if not d['calibrated']:return '等待归中'
    if d['out_of_range']:return '水平航向越界（±90°）'
    if d['drift']:return '检测到姿态跳变，需归中'
    if d['accuracy']<2:return '姿态精度不足'
    if not d['fresh']:return '实时报告超时'
    if d.get('snapshot_blocked'):return '击发前历史不足：等待30～80ms内有效音区/C档快照'
    if not d['armed']:return '等待静止准备／击发间隔'
    return '已准备，可下拍'
def execute(c,j,action,p):
    e=c.engine
    if not e.ready:raise ValueError('尚未连接或握手未完成')
    if not e.capabilities.get('imu_diagnostic'):raise ValueError('需要GEST25诊断固件；旧固件未提供')
    if action=='diagnostic.query':return dict(source=e.source,diagnostic=e.instrument_state.get('diagnostic'),gesture=e.instrument_state.get('gesture'),output_mute=e.instrument_state.get('output_mute'),hit_events=list(e.hit_events))
    if action=='diagnostic.direction':
        if not e.capabilities.get('gesture_stable26'):raise ValueError('需要GEST26固件')
        if set(p)!={'hand','invert'} or type(p['hand']) is not int or p['hand'] not in (0,1) or type(p['invert']) is not bool:raise ValueError('hand须为0/1，invert须为布尔值')
        if e.duo.get('running'):raise ValueError('请先停止演奏，再改转向方向；改后需重新归中')
        before=e.duo_revision;c.ack(j,e.send(68,bytes([p['hand'],p['invert']])))
        c.wait(j,lambda:e.duo_revision>before and e.instrument_state.get('yaw_invert',[None,None])[p['hand']]==p['invert'],3,'方向设置读回超时')
        return dict(accepted=True,invert=p['invert'],hand=p['hand'],note='方向已应用，需重新归中')
    if action=='diagnostic.mute':
        if set(p)!={'muted'} or type(p['muted']) is not bool:raise ValueError('muted须为布尔值')
        before=e.duo_revision;c.ack(j,e.send(67,bytes([p['muted']])))
        c.wait(j,lambda:e.duo_revision>before and e.instrument_state.get('output_mute')==p['muted'],3,'静音状态读回超时')
        return dict(muted=p['muted'],accepted=True)
    h=p.get('hand')
    if set(p)!={'hand'} or type(h) is not int or h not in (0,1):raise ValueError('hand须为0或1')
    if action=='diagnostic.center' and not (e.instrument_state.get('online',0)>>h)&1:raise ValueError('所选手IMU报告未齐，不能归中')
    c.ack(j,e.send(60,struct.pack('<BH',25 if action=='diagnostic.center' else 28,h)))
    return dict(accepted=True,hand=h,note='请求已接受；请查看后续归中进度或复位计数，非完成判定')
def build_controls(gui,layout):
    from PySide6 import QtWidgets as W
    import pyqtgraph as pg
    box=W.QGroupBox('真实IMU诊断与下拍确认 · 低音量测试');col=W.QVBoxLayout(box)
    row=W.QHBoxLayout();gui.diag_hand=W.QComboBox();gui.diag_hand.addItems(['左手','右手']);row.addWidget(gui.diag_hand)
    def send(a,p):gui.safe(lambda:gui.submit_command(a,p))
    b=W.QPushButton('归中当前手');b.clicked.connect(lambda:send('diagnostic.center',{'hand':gui.diag_hand.currentIndex()}));row.addWidget(b)
    def reset():
        if W.QMessageBox.question(gui,'复位IMU','复位当前手会中断数据并清除该手归中，是否继续？')==W.QMessageBox.StandardButton.Yes:send('diagnostic.reset',{'hand':gui.diag_hand.currentIndex()})
    b=W.QPushButton('复位当前手IMU');b.clicked.connect(reset);row.addWidget(b)
    gui.diag_mute=W.QCheckBox('输出静音（检测与板内波形继续）');gui.diag_mute.clicked.connect(lambda v:send('diagnostic.mute',{'muted':v}));row.addWidget(gui.diag_mute)
    b=W.QPushButton('导出诊断CSV');b.clicked.connect(lambda:export_csv(gui));row.addWidget(b)
    b=W.QPushButton('清空测试统计');b.clicked.connect(lambda:clear(gui));row.addWidget(b);col.addLayout(row)
    row=W.QHBoxLayout();gui.diag_yaw_invert=W.QCheckBox('当前手左右转向反向（停止后可改，改后归中）')
    gui.diag_yaw_invert.clicked.connect(lambda v:send('diagnostic.direction',{'hand':gui.diag_hand.currentIndex(),'invert':v}));row.addWidget(gui.diag_yaw_invert)
    gui.diag_marks={};gui.diag_mark_label=W.QLabel('归中后静止，分别记录左转20°、回中、右转20°；用于检查方向和对称性，非自动标定。');gui.diag_mark_label.setWordWrap(True)
    def mark(name):
        h=gui.diag_hand.currentIndex();data=gui.engine.instrument_state.get('diagnostic',[])
        if not gui.engine.ready or len(data)!=2 or not data[h]['fresh']:return
        gui.diag_marks[(h,name)]=data[h]['yaw'];gui.diag_mark_label.setText('；'.join(f"{'左手' if k[0]==0 else '右手'} {k[1]}：{v:+.1f}°" for k,v in gui.diag_marks.items()))
    for name in ('左转20°','回中','右转20°'):
        b=W.QPushButton('记录'+name);b.clicked.connect(lambda checked=False,n=name:mark(n));row.addWidget(b)
    col.addLayout(row);col.addWidget(gui.diag_mark_label)
    row=W.QHBoxLayout();gui.diag_cards=[]
    for h in (0,1):
        l=W.QLabel(('左手' if h==0 else '右手')+'：固件未提供诊断');l.setWordWrap(True);l.setMinimumWidth(260);row.addWidget(l);gui.diag_cards.append(l)
    col.addLayout(row)
    gui.diag_plot=pg.PlotWidget(title='Z线性加速度状态抽样（非峰值记录）：下拍为负Z；虚线 −2.5 m/s²（也可由突变触发）');gui.diag_plot.setMaximumHeight(130);gui.diag_plot.setLabel('left','加速度','m/s²');gui.diag_plot.setLabel('bottom','电脑接收相对时间','s');gui.diag_lines=[gui.diag_plot.plot(pen=c) for c in ('#53dfc2','#79abff')];gui.diag_plot.addItem(pg.InfiniteLine(pos=-2.5,angle=0,pen=pg.mkPen('#ffbf60',style=__import__('PySide6.QtCore',fromlist=['Qt']).Qt.PenStyle.DashLine)));col.addWidget(gui.diag_plot)
    gui.diag_events=W.QPlainTextEdit('最近击发：尚无；短时间多次击发会合并计数');gui.diag_events.setReadOnly(True);gui.diag_events.setMaximumHeight(100);col.addWidget(gui.diag_events)
    layout.addWidget(box);gui.diag_box=box;gui.diag_seen=[None,None];gui.diag_base=[0,0];gui.diag_flash=[0,0];gui.diag_history=deque(maxlen=20);gui.diag_data=[deque(maxlen=120),deque(maxlen=120)];gui.diag_event_seen=0;gui.diag_revision=-1;gui.diag_start=time.monotonic();gui.diag_received=0;gui.diag_rows=deque(maxlen=3600)
def clear(g):
    g.diag_base=list(g.engine.duo.get('hits',[0,0]));g.diag_history.clear();g.diag_rows.clear();g.diag_event_seen=getattr(g.engine,'hit_event_revision',0);g.diag_flash=[0,0];g.diag_marks.clear();g.diag_mark_label.setText('观察记录已清空：左转20°、回中、右转20°，分别记录。')
    for a in g.diag_data:a.clear()
def refresh(g):
    from PySide6 import QtCore as C
    e=g.engine;s=e.instrument_state;now=time.monotonic();d=s.get('diagnostic')
    supported=e.capabilities.get('imu_diagnostic',False)
    g.diag_yaw_invert.setEnabled(bool(e.ready and e.capabilities.get('gesture_stable26') and not e.duo.get('running')))
    with C.QSignalBlocker(g.diag_yaw_invert):g.diag_yaw_invert.setChecked(s.get('yaw_invert',[False,False])[g.diag_hand.currentIndex()])
    if getattr(e,'hit_event_revision',0)<g.diag_event_seen:g.diag_event_seen=0
    if getattr(e,'hit_event_revision',0)!=g.diag_event_seen:
        for ev in e.hit_events[-min(20,e.hit_event_revision-g.diag_event_seen):]:
            h=ev['hand'];g.diag_flash[h]=now+.5;g.diag_history.appendleft(f"{'左' if h==0 else '右'} 下拍#{ev['count']} 音区{ev['zone']+1} C{[4,5,2,3][ev['octave']]} 板上时刻{ev['board_tick']/50000000:.6f}s；快照提前{str(ev['snapshot_age_ms'])+'ms' if ev['snapshot_age_ms'] is not None else '不适用（教学/旧手势）'}")
        g.diag_event_seen=e.hit_event_revision
    g.diag_mute.setEnabled(bool(e.ready and supported))
    if not supported or not d:
        for l in g.diag_cards:l.setText('固件未提供IMU诊断；需重新编译下载GEST25，旧击发累计：'+str(e.duo.get('hits')))
        return
    new=e.duo_revision!=g.diag_revision
    if new:
        g.diag_revision=e.duo_revision;g.diag_received=now
        for h,x in enumerate(d):g.diag_rows.append(dict(pc_time=time.time(),source=e.source,hand=h,hit_events=list(e.hit_events),**x))
    stale=not e.ready or now-g.diag_received>1
    with C.QSignalBlocker(g.diag_mute):g.diag_mute.setChecked(s.get('output_mute',False))
    for h,x in enumerate(d):
        count=x['hits'];last=g.diag_seen[h]
        if new and not e.capabilities.get('gesture_stable26') and last is not None and count>last:
            g.diag_flash[h]=now+.5;g.diag_history.appendleft(f"{time.strftime('%H:%M:%S')} {'左' if h==0 else '右'} 下拍 +{count-last}，锁存音区{x['hit_zone']+1}，触发类型{x['trigger']}")
        if new:g.diag_seen[h]=count
        gs=s.get('gesture',{});code=gs.get('octave_codes',[0,0])[h];snap=gs.get('snapshot_codes',[0,0])[h]
        if x.get('extension')==2:snap=x['snapshot_octave']
        candidate=s.get('gesture_candidates',[{},{}])[h]
        label=('左手' if h==0 else '右手')+(' ✓ 下拍已检测' if now<g.diag_flash[h] else '')
        g.diag_cards[h].setText(f"{label} · 候选C{[4,5,2,3][candidate.get('candidate',0)]} 稳定{candidate.get('stable_ms',0)}ms · 测试累计{max(0,count-g.diag_base[h])}（板上{count}）\n"+('串口数据过期' if stale else reason(x))+f" · 稳定C{[4,5,2,3][code]} / 当前下拍将采用C{[4,5,2,3][snap]}\n音区{x['zone']+1}；航向{x['yaw']:.1f}° 俯仰{x['pitch']:.1f}° 横滚{x['roll']:.1f}°\n选档俯仰{candidate.get('filtered_pitch',0):.1f}°（已计方向与滤波）；边界−30/−10/+20°，迟滞3°；归中{x['progress']}/50，精度{x['accuracy']}\n姿态/加速/角速 Hz：{x['rates']}；年龄ms：{[round(a,1) for a in x['ages_ms']]}\n协议错误{x['protocol_errors']} 序号缺失{x['sequence_gaps']} 复位{x['resets']}\n首次故障{FAILURES.get(x['first_failure'],x['first_failure'])}；最近{FAILURES.get(x['last_failure'],x['last_failure'])}")
        if x.get('extension')==2:g.diag_cards[h].setText(g.diag_cards[h].text()+f"\n线性加速度实收{x['linear_hz']}Hz / 最近间隔{x['linear_interval_ms']:.1f}ms；过滤航向{x['filtered_yaw']:+.1f}°；候选音区{x['zone_candidate']+1}；成对快照音区{x['snapshot_zone']+1} {'有效' if x['snapshot_valid'] else '无效'}")
        g.diag_cards[h].setStyleSheet('background:#145f42;color:white;padding:8px;' if now<g.diag_flash[h] else 'background:#172a38;padding:8px;')
        if new and not stale:g.diag_data[h].append((now-g.diag_start,x['linear_z'] if x['ages_ms'][3]<40 else float('nan')))
        a=list(g.diag_data[h]);
        if new:g.diag_lines[h].setData([v[0] for v in a],[v[1] for v in a],connect='finite')
    event_text='最近击发（新事件保持500ms）：\n'+'\n'.join(list(g.diag_history)[:20])
    if g.diag_events.toPlainText()!=event_text:g.diag_events.setPlainText(event_text)

def export_csv(g):
    import csv,json
    from PySide6 import QtWidgets as W
    path,_=W.QFileDialog.getSaveFileName(g,'导出IMU诊断','IMU诊断.csv','CSV (*.csv)')
    if not path:return
    rows=list(g.diag_rows)

    if not rows:return
    with open(path,'w',encoding='utf-8-sig',newline='') as f:
        fields=list(dict.fromkeys(k for row in rows for k in row));w=csv.DictWriter(f,fieldnames=fields);w.writeheader()
        for r in rows:w.writerow({k:json.dumps(v,ensure_ascii=False) if isinstance(v,(list,dict)) else v for k,v in r.items()})


def decode_event(b):
    if len(b)!=32 or b[0]!=1 or b[1]>1 or b[2]>11 or b[3]>3 or b[4]>2:raise ValueError('击发事件报文格式错误')
    count,board,sensor,snapshot,drops=struct.unpack_from('<5I',b,8)
    age=((sensor-snapshot)&0xffffffff)/10 if b[7]&1 else None
    if age is not None and not 30<=age<=80:raise ValueError('击发快照时间越界')
    return dict(hand=b[1],zone=b[2],octave=b[3],profile=b[4],velocity=b[5],reason=b[6],count=count,board_tick=board,sensor_tick=sensor,snapshot_tick=snapshot,snapshot_age_ms=age,uses_snapshot=bool(b[7]&1),event_drops=drops)
