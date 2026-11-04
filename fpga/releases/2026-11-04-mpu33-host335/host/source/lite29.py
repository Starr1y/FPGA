"""TangLab 3.3.1: four-page instrument frontend, shared serial scheduler."""
import sys,time,csv,struct
from pathlib import Path
import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore as C,QtGui as G,QtWidgets as W
from lab_engine import LabEngine
from lab_agent import CommandController
from lab_duo_ui import MouseFan
from lab_ui import ChineseViewBox,setup_plot,chinese_qt
import lab_score_ui
from lab_key30_theme import apply as apply_theme, plot_style
ROOT=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
class Window(W.QMainWindow):
 def __init__(self):
  super().__init__();self.engine=LabEngine();self.controller=CommandController(self.engine,ROOT);self.jobs=set();self.capture_job=None;self.next_capture=0;self.revision=-1;self.key_masks=[0,0];self.pitch_values=[0.,0.];self.event_id=0;self.keyboard_down=set();self.lesson_keys_down=set();self.mouse_zones=[None,None];self.expression_at=[0.,0.];self.pose_sent=0.;self.keyboard_jobs=set();self.chord_dirty=False;self.chord_job=None
  self.setWindowTitle('TangLab 3.3.5 · 键鼠手柄演示');self.resize(1280,850)
  apply_theme(self)
  body=W.QWidget();body.setObjectName('appBody');self.setCentralWidget(body);col=W.QVBoxLayout(body);col.setContentsMargins(18,16,18,10);col.setSpacing(10)
  header=W.QFrame();header.setObjectName('headerCard');head=W.QHBoxLayout(header);head.setContentsMargins(18,12,18,12)
  brand=W.QVBoxLayout();logo=W.QLabel('TANGLAB');logo.setObjectName('brand');brand.addWidget(logo)
  subtitle=W.QLabel('双手演奏');subtitle.setObjectName('subtitle');brand.addWidget(subtitle);head.addLayout(brand);head.addStretch()
  self.banner=W.QLabel('未连接');self.banner.setObjectName('connectionStatus');self.banner.setWordWrap(True);head.addWidget(self.banner,1);col.addWidget(header)
  row=W.QHBoxLayout();self.port=W.QComboBox();row.addWidget(self.port,1);self.button(row,'刷新串口',self.ports);self.button(row,'连接',self.connect_board);self.button(row,'断开',lambda:self.submit_command('disconnect'));self.button(row,'模拟演示',self.demo);col.addLayout(row)
  self.tabs=W.QTabWidget();col.addWidget(self.tabs)
  self.performance_page();self.scope_page();self.settings_page();lab_score_ui.build(self);self.tabs.setTabText(3,'04 曲谱上传与教学')
  self.duo_sync=W.QCheckBox();self.duo_sync.setChecked(False)
  diagnostics=W.QWidget();dl=W.QVBoxLayout(diagnostics);dl.setContentsMargins(0,0,0,0)
  detail_toggle=W.QToolButton();detail_toggle.setText('连接详情（展开）');detail_toggle.setCheckable(True);detail_toggle.setStyleSheet('QToolButton{background:transparent;border:0;padding:3px;color:#706659;}');dl.addWidget(detail_toggle,0,C.Qt.AlignmentFlag.AlignLeft)
  self.connection_details=W.QLabel();self.connection_details.setWordWrap(True);self.connection_details.setTextInteractionFlags(C.Qt.TextInteractionFlag.TextSelectableByMouse);dl.addWidget(self.connection_details);self.connection_details.hide();detail_toggle.toggled.connect(self.connection_details.setVisible);detail_toggle.toggled.connect(lambda on:detail_toggle.setText('连接详情（收起）' if on else '连接详情（展开）'));col.addWidget(diagnostics)
  self.timer=C.QTimer(self);self.timer.timeout.connect(self.refresh);self.timer.start(50);self.pose_timer=C.QTimer(self);self.pose_timer.timeout.connect(self.pose_heartbeat);self.pose_timer.start(20);self.ports();W.QApplication.instance().installEventFilter(self)
 def safe(self,fn):
  try:return fn()
  except Exception as exc:W.QMessageBox.warning(self,'操作未完成',str(exc))
 def button(self,row,text,fn):
  b=W.QPushButton(text);b.setProperty('role','stop' if '停止' in text else 'primary' if text in ('开始鼠标演奏','应用演奏设置','连接') else 'normal');b.clicked.connect(lambda:self.safe(fn));row.addWidget(b);return b
 def page(self,title):
  p=W.QWidget();outer=W.QVBoxLayout(p);outer.setContentsMargins(0,0,0,0)
  if title.startswith('03'):
   scroll=W.QScrollArea();scroll.setWidgetResizable(True);body=W.QWidget();scroll.setWidget(body);outer.addWidget(scroll);l=W.QVBoxLayout(body)
  else:l=outer
  l.setContentsMargins(16,18,16,16);l.setSpacing(12);self.tabs.addTab(p,title);return l
 def submit_command(self,action,params=None):
  j=self.controller.submit(action,params or {});self.jobs.add(j['id']);return j
 def ports(self):
  from serial.tools.list_ports import comports
  self.port.clear()
  for p in comports():self.port.addItem(p.device+' · '+p.description,p.device)
 def connect_board(self):
  if not self.port.currentData():raise ValueError('未发现串口，请连接DEBUG-USB2并检查驱动')
  self.stop_live();self.submit_command('connect',dict(port=self.port.currentData(),baud=921600))
 def demo(self):self.stop_live();self.submit_command('score.demo')
 def performance_page(self):
  l=self.page('01 演奏与鼠标模拟');row=W.QHBoxLayout();self.button(row,'开始鼠标演奏',self.start_mouse);self.button(row,'全局停止',lambda:self.submit_command('duo.stop'));l.addLayout(row)
  self.keyboard_enabled=W.QCheckBox('开启键盘演奏');self.keyboard_enabled.setToolTip('仅演奏页、鼠标演奏已启动时生效；每次按下击发一次，按住不连发。');l.addWidget(self.keyboard_enabled)
  self.input_mode=W.QComboBox();self.input_mode.addItems(['鼠标选区 + W/S、O/L击发','数字演奏：主键盘左手 / 小键盘右手']);self.input_mode.setToolTip('数字模式需要Num Lock开启；两侧1～7为DO～SI，W升右手八度、S降右手八度。切换模式后重新开始演奏。');l.addWidget(self.input_mode)
  self.keyboard_hint=W.QLabel('鼠标选区；左手 W轻音 / S轻音 / A表情；右手 O轻音 / L轻音 / K表情。空格停止。');self.keyboard_hint.setWordWrap(True);l.addWidget(self.keyboard_hint)
  self.play_hint=W.QLabel('连接板卡→开始鼠标演奏→开启键盘演奏。鼠标分别选区，W/S左手轻音，O/L右手轻音；按住不连发。所有击发均为轻音短按。\nA/K为左右表情键：按住并拖动俯仰滑条模拟手腕；开启滑音后，按住A/K、选目标区、按击发键确认滑音。空格停止。');self.play_hint.setWordWrap(True);l.addWidget(self.play_hint)
  angle_hint=W.QLabel('七音沿用30版：总范围±90°，FA位于中央。归中后保持原朝向，应位于FA。');angle_hint.setWordWrap(True);l.addWidget(angle_hint)
  self.tabs.widget(0).setToolTip('S1发音：俯仰小于0°为低音，0～30°为中音，大于30°为高音。S2先按再于80ms内按S1确认滑音；单独长按180ms进入手腕表情。')
  self.fans=[];self.pitch_sliders=[];self.octave_boxes=[];row=W.QHBoxLayout()
  for h in range(2):
   box=W.QGroupBox('左手' if h==0 else '右手');box.setProperty('hand','left' if h==0 else 'right');v=W.QVBoxLayout(box);fan=MouseFan(h);fan.hdmi_theme=True;fan.setMinimumHeight(220);fan.selected.connect(lambda z,h=h:self.select_duo(h,z));fan.struck.connect(lambda z,h=h:self.strike_duo(h,z));v.addWidget(fan,1);self.fans.append(fan)
   buttons=W.QGridLayout()
   for k,label in enumerate(['S1 发音','S2 表情']):
    b=W.QPushButton('S1 轻音' if k==0 else 'S2 表情保持');b.setProperty('role','left' if h==0 else 'right');b.setCheckable(k==1);b.setToolTip('S1点击只发一次轻音；S2可保持表情。');b.toggled.connect(lambda on,h=h,k=k:self.key_change(h,k,on)) if k else b.clicked.connect(lambda checked=False,h=h:self.short_key(h,0));buttons.addWidget(b,0,k)
    short=W.QPushButton('短按S1' if k==0 else 'S2+S1 快捷滑音');short.clicked.connect(lambda checked=False,h=h,k=k:self.short_key(h,k));buttons.addWidget(short,1,k)
   v.addLayout(buttons);pitch=W.QSlider(C.Qt.Orientation.Horizontal);pitch.setRange(-450,450);pitch.setValue(150);self.pitch_sliders.append(pitch);self.pitch_values[h]=15.;pitch.valueChanged.connect(lambda x,h=h:self.pitch_change(h,x/10));v.addWidget(W.QLabel('虚拟俯仰：拖动滑条模拟抬腕／压腕'));v.addWidget(pitch);octave=W.QComboBox();octave.addItems(['低音 C3','中音 C4','高音 C5']);octave.setCurrentIndex(1);self.octave_boxes.append(octave);octave.currentIndexChanged.connect(lambda i,p=pitch:p.setValue([-150,150,400][i]));v.addWidget(octave);row.addWidget(box)
  self.input_mode.currentIndexChanged.connect(self.change_input_mode)
  self.keyboard_enabled.toggled.connect(lambda on:self.release_keyboard() if not on else None);self.tabs.currentChanged.connect(lambda i:self.release_keyboard() if i!=0 else None)
  l.addLayout(row,1);self.mpu_summary=W.QLabel('手柄状态：等待设备');self.mpu_summary.setWordWrap(True);l.addWidget(self.mpu_summary);self.play_status=W.QLabel('等待板上状态');self.play_status.setWordWrap(True);l.addWidget(self.play_status)
 def short_key(self,h,k):
  if k==0:self.strike_duo(h,self.fans[h].hover or 0)
  else:self.safe(lambda:self.submit_command('keys30.slide',dict(hand=h,zone=self.fans[h].hover or 0,pitch=self.pitch_values[h])))
 def key_change(self,h,k,on):
  self.key_masks[h]=(self.key_masks[h]|1<<k) if on else (self.key_masks[h]&~(1<<k));self.send_keys(h)
 def pitch_change(self,h,value):self.pitch_values[h]=value;self.send_keys(h)
 def send_keys(self,h):self.safe(lambda:self.submit_command('lite.keys',dict(hand=h,mask=self.key_masks[h],pitch=self.pitch_values[h])))
 def select_duo(self,h,z):
  if z is None and self.keyboard_enabled.isChecked():
   self.fans[h].hover=self.mouse_zones[h];self.fans[h].update();return
  self.mouse_zones[h]=z
  if self.engine.ready:self.safe(lambda:self.submit_command('duo.select',dict(hand=h,valid=z is not None,zone=z or 0)))
 def strike_duo(self,h,z):
  if not self.engine.ready:return
  self.safe(lambda:self.submit_command('keys30.strike',dict(hand=h,zone=z,pitch=self.pitch_values[h],release_mask=self.key_masks[h]&2)))
 def start_mouse(self):
  if 'KEY30' not in self.engine.device and not self.engine.source.startswith('模拟'):raise ValueError('请先下载V14双手配套固件')
  self.submit_command('instrument.set',dict(mode=1));self.submit_command('duo.configure',dict(run=True,profiles=[self.profile.currentIndex()]*2,presets=[x.currentIndex() for x in self.timbres],gain=self.volume.value(),hold_ms=[self.hold.value()]*2,release_ids=[self.release.currentIndex()]*2,chord=self.chord.currentIndex()==1,effect=self.effect.currentIndex(),wet=self.wet.value()))
 def scope_page(self):
  l=self.page('02 整体波形');row=W.QHBoxLayout();self.continuous=W.QCheckBox('连续512点监测');row.addWidget(self.continuous);self.pause=W.QCheckBox('暂停绘图');row.addWidget(self.pause);self.button(row,'单次512点',self.capture);self.button(row,'导出CSV',self.export_csv);l.addLayout(row)
  hint=W.QLabel('查看左右输出及混音：勾选连续监测，或单次抓取512点。滚轮缩放、拖动平移，右键打开中文菜单。\n采样率48 kHz；分段采集，段间有空档。“暂停绘图”冻结画面，CSV导出最近一段完整采样。');hint.setWordWrap(True);l.addWidget(hint)
  self.curves=[]
  for label,color in [('左输出','#e94e36'),('右输出','#c47a18'),('混音','#44475b')]:
   plot=pg.PlotWidget(viewBox=ChineseViewBox());setup_plot(plot);plot_style(plot);plot.setLabel('left',label+'（PCM）');plot.setLabel('bottom','时间（ms）');self.curves.append(plot.plot(pen=color));l.addWidget(plot)
  self.scope_note=W.QLabel('等待完整采样');l.addWidget(self.scope_note)
 def capture(self):self.capture_job=self.submit_command('capture',dict(points=512,trigger=0))['id']
 def stop_live(self,*args):self.continuous.setChecked(False)
 def export_csv(self):
  a=self.engine.audio
  if a is None:raise ValueError('尚无完整样本')
  path,_=W.QFileDialog.getSaveFileName(self,'导出整体波形','整体波形.csv','CSV (*.csv)')
  if path:
   with open(path,'w',newline='',encoding='utf-8-sig') as f:
    w=csv.writer(f);w.writerow(['时间_ms','左输出_PCM','右输出_PCM','混音_PCM']);w.writerows((i*1000/self.engine.fs,*map(int,a[i,2:5])) for i in range(len(a)))
 def settings_page(self):
  l=self.page('03 模式与硬件设置');hint=W.QLabel('修改参数后点击“应用演奏设置”。实物测试：切换手柄 → 保持静止并分别归中 → 开始手柄演奏。\n保持时间决定何时松键，释音决定松键后多久收音；乐器自然衰减仍会使声音逐渐变轻。');hint.setWordWrap(True);l.addWidget(hint);form=W.QFormLayout();l.addLayout(form);self.timbres=[]
  native=W.QGroupBox('MPU连接与归中');native.setVisible(False);nv=W.QVBoxLayout(native);self.mpu_details=W.QLabel('等待设备提供诊断');self.mpu_details.setWordWrap(True);nv.addWidget(self.mpu_details)
  nr=W.QHBoxLayout();self.compat75=[]
  for label in ['左手允许异常身份兼容','右手允许异常身份兼容']:
   cb=W.QCheckBox(label);cb.setToolTip('仅诊断：允许身份读值0x75。它不等同于正常MPU6050身份，需先停止演奏。更改后对应采集链路会重新初始化。');nr.addWidget(cb);self.compat75.append(cb)
  self.mpu_apply=self.button(nr,'应用兼容设置',lambda:self.submit_command('mpu.configure',dict(allow_identity75=sum(int(cb.isChecked())<<h for h,cb in enumerate(self.compat75)))))
  self.mpu_query=self.button(nr,'刷新手柄状态',lambda:self.submit_command('mpu.status'));nv.addLayout(nr);l.insertWidget(1,native)
  for label in ['左手音色','右手音色']:
   c=W.QComboBox();c.addItems(['钢琴','马林巴','电钢琴','拨弦']);self.timbres.append(c);form.addRow(label,c)
  self.profile=W.QComboBox();self.profile.addItems(['七音','五音','十二音']);form.addRow('音区布局',self.profile)
  self.volume=W.QSpinBox();self.volume.setRange(0,256);self.volume.setValue(8);form.addRow('总音量 /256',self.volume)
  self.hold=W.QSpinBox();self.hold.setRange(100,10000);self.hold.setValue(1500);form.addRow('保持（ms）',self.hold)
  self.release=W.QComboBox();self.release.addItems(['0.2秒','0.5秒','1.5秒']);self.release.setCurrentIndex(1);form.addRow('释音',self.release)
  self.chord=W.QComboBox();self.chord.addItems(['单音','三音和弦']);self.chord.activated.connect(lambda _:setattr(self,'chord_dirty',True));form.addRow('左手演奏',self.chord);chord_hint=W.QLabel('右手始终单音。七音和弦按音阶叠三度，例如DO→DO/MI/SOL；五音、十二音使用根音+4/+7半音。\n改变左手模式并应用后停止演奏，请重新开始；教学仍按单音作答。');chord_hint.setWordWrap(True);form.addRow(chord_hint)
  self.effect=W.QComboBox();self.effect.addItems(['旁路','回声','混响']);form.addRow('音效',self.effect)
  self.wet=W.QSpinBox();self.wet.setRange(0,255);self.wet.setValue(64);form.addRow('音效比例 /255',self.wet)
  self.glide=W.QCheckBox('滑音');self.vibrato=W.QCheckBox('颤音');form.addRow(self.glide);form.addRow(self.vibrato)
  self.glide_ms=W.QSpinBox();self.glide_ms.setRange(20,500);self.glide_ms.setValue(80);form.addRow('滑音（ms）',self.glide_ms)
  row=W.QHBoxLayout();self.button(row,'应用演奏设置',self.apply_settings);self.button(row,'切换手柄',lambda:self.submit_command('instrument.set',dict(mode=0)));self.button(row,'开始手柄演奏',lambda:self.submit_command('instrument.set',dict(run=1)));l.addLayout(row)
  row=W.QHBoxLayout()
  for h,label in enumerate(['左手归中','右手归中']):self.button(row,label,lambda h=h:self.submit_command('diagnostic.center',dict(hand=h)))
  self.mute=W.QCheckBox('输出静音');self.mute.toggled.connect(lambda on:self.safe(lambda:self.submit_command('diagnostic.mute',dict(muted=on))));row.addWidget(self.mute);l.addLayout(row);l.addStretch()
 def apply_settings(self):
  p=dict(left_timbre=self.timbres[0].currentIndex(),right_timbre=self.timbres[1].currentIndex(),left_scale=self.profile.currentIndex(),right_scale=self.profile.currentIndex(),volume=self.volume.value(),left_hold_ms=self.hold.value(),right_hold_ms=self.hold.value(),left_release=self.release.currentIndex(),right_release=self.release.currentIndex(),chord=self.chord.currentIndex()==1,effect=self.effect.currentIndex(),wet=self.wet.value())
  self.chord_job=self.submit_command('instrument.set',p)['id'];self.submit_command('lite.configure',dict(glide=3 if self.glide.isChecked() else 0,vibrato=3 if self.vibrato.isChecked() else 0,glide_ms=self.glide_ms.value()))
 def refresh(self):
  e=self.engine;self.connection_details.setText(f'版本：3.3.5\n来源：{e.source}\n设备：{e.device}\n详情：{e.status}');self.banner.setText(('模拟演示' if e.source.startswith('模拟') else '已连接' if e.ready else '未连接')+' · '+(e.status[:55] if e.status else '就绪'));self.banner.setToolTip(e.status);lab_score_ui.refresh(self)
  for jid in list(self.jobs):
   j=self.controller.job(jid)
   if j['state'] in ('completed','failed','cancelled'):
    self.jobs.discard(jid)
    if j['state']=='failed':e.status='操作失败：'+j['message']
  if self.chord_job:
   job=self.controller.job(self.chord_job)
   if job['state'] in ('completed','failed','cancelled'):
    if job['state']=='completed':self.chord_dirty=False
    self.chord_job=None
  if e.ready and 'chord' in e.duo_config and not self.chord_dirty and not self.chord_job:
   self.chord.blockSignals(True);self.chord.setCurrentIndex(int(bool(e.duo_config['chord'])));self.chord.blockSignals(False)
  if self.capture_job:
   j=self.controller.job(self.capture_job)
   if j['state'] in ('completed','failed','cancelled'):
    self.capture_job=None;self.next_capture=time.monotonic()+.02
    if j['state']=='failed':self.stop_live();self.scope_note.setText(j['message'])
  if self.continuous.isChecked() and not self.capture_job and self.controller.active is None and self.controller.queue.empty() and time.monotonic()>=self.next_capture:
   if e.ready:self.safe(self.capture)
   else:self.stop_live()
  if e.audio is not None and not self.pause.isChecked() and self.revision!=e.audio_revision:
   a=e.audio.copy();t=np.arange(len(a))*1000/e.fs
   for curve,k in zip(self.curves,[2,3,4]):curve.setData(t,a[:,k])
   self.revision=e.audio_revision;self.scope_note.setText(f'完整{len(a)}点，采样率{e.fs}Hz；分段采集，段间有空档')
  from lab_mpu_native import describe
  m=getattr(e,'mpu_native',{});supported=e.capabilities.get('mpu_native_v11',False)
  self.mpu_apply.setEnabled(e.ready and supported);self.mpu_query.setEnabled(e.ready and supported)
  text=describe(m,e.ready,supported) if supported else '沿用30版手柄接线与归中。S1短按轻音，长按220ms重音。'
  self.mpu_summary.setText(text);angles=e.instrument_state.get('diagnostic',[]);angle_text='\n'.join(f"{'左' if h==0 else '右'}手归中观察：航向 {x.get('yaw',0):.1f}°，音区 {x.get('zone',0)+1}；FA中心0°" for h,x in enumerate(angles))
  self.mpu_details.setText(text+'\n'+angle_text+'\n接线：左INT J13.38、S2 J13.36；右INT J13.31、S2 J13.32。两手均按MPU +X朝上、+Y箭头朝前安装。先确认在线，再静止并归中；保持原朝向应为FA。')
  self.mpu_summary.setToolTip('详细错误、身份、INT计数和样本年龄见设置页；兼容模式只用于诊断。')
  if self.keyboard_down and (not e.ready or e.instrument_state.get('mode')!=1 or not e.duo.get('running')):self.release_keyboard()
  self.update_keyboard_hint()
  for h,fan in enumerate(self.fans):fan.profile=self.keyboard_profile(h);fan.update()
  if not e.ready:self.play_status.setText('请先连接设备；鼠标测试从“开始鼠标演奏”进入，实物演奏请到设置页切换手柄并归中。');return
  s=e.instrument_state;g=s.get('gesture',{});lines=[]
  for h,label in enumerate(['左手','右手']):
   key=s.get('keys30',[{},{}])[h];codes=g.get('octave_codes',[0,0]);snap=g.get('snapshot_codes',[0,0]);mask=key.get('pressed',0)
   diag=s.get('diagnostic',[]);pitch=(diag[h].get('pitch') if len(diag)>h else None)
   if s.get('mode')==1:pitch=self.pitch_values[h]
   zone=e.duo.get('selected',[None,None])[h];zone_text=str(zone+1) if zone is not None else '—'
   amount=key.get('strength');strength='轻' if amount==48 else '重' if amount==112 else '中' if amount==80 else '—'
   expr='表情中' if g.get('pressed',[False,False])[h] else '待演奏';block=key.get('blocked',0)
   reason={1:'姿态暂不可用',2:'请先选择音区'}.get(block,'')
   lines.append(f"{label}  音区 {zone_text} · 俯仰 {pitch:.1f}°" if isinstance(pitch,(int,float)) else f"{label}  音区 {zone_text} · 俯仰 —")
   lines[-1]+=f" · 预览 C{[4,5,2,3][codes[h]]} / 击发 C{[4,5,2,3][snap[h]]} · {strength} · S1 {'按下' if mask&1 else '松开'} / S2 {'按下' if mask&2 else '松开'} · {reason or expr}"
   if len(diag)>h:
    d=diag[h];fail=d.get('last_failure',0);header=d.get('header',0)
    reasons={0:'无',2:'I²C事务失败',4:'身份不支持',5:'配置读回不一致',6:'采样超时'}
    lines[-1]+=f"\n  采集{'在线' if d.get('online') else '离线'} · 最近故障 {fail}:{reasons.get(fail,'其他')} · 寄存器0x{header>>8:02X} · I²C错误 {d.get('protocol_errors',0)} · 自动复位 {d.get('resets',0)} · 姿态年龄{d.get('ages_ms',[0])[0]:.1f}ms"

  self.play_status.setText(('板上模式：左手三音和弦 · 右手单音' if e.duo_config.get('chord') else '板上模式：左手单音 · 右手单音')+'\n'+'\n'.join(lines))
 def change_input_mode(self,index):
  self.release_keyboard()
  for box in self.octave_boxes:box.setCurrentIndex(1)
  self.update_keyboard_hint()
  if self.engine.ready and self.engine.duo.get('running'):self.safe(lambda:self.submit_command('duo.stop'))
 def update_keyboard_hint(self):
  numeric=self.input_mode.currentIndex()==1
  if numeric:
   self.keyboard_hint.setText('主键盘1～7＝左手DO～SI；小键盘1～7＝右手DO～SI（Num Lock开启）。W升右手一档，S降一档，C3/C4/C5。')
   self.play_hint.setText('数字按下直接选音并击发，无需鼠标；按住不连发。A/K仍为左右表情键，空格停止。左手和弦保持C4，右手默认C4。《小星星》全曲不按W/S。数字模式使用七音布局。')
  else:
   self.keyboard_hint.setText('鼠标选区；左手W轻音 / S轻音 / A表情；右手O轻音 / L轻音 / K表情。空格停止。')
   self.play_hint.setText('鼠标分别选择并保留音区；W/O轻音约220ms后增强，S/L轻音。按住A/K并拖动俯仰滑条模拟手腕；开启滑音后选目标区再击发确认。')
  chord=bool(self.engine.duo_config.get('chord'))
  self.octave_boxes[0].setEnabled(not (numeric and chord));self.pitch_sliders[0].setEnabled(not (numeric and chord))
  if numeric and chord:self.pitch_sliders[0].setValue(150)
  if numeric and chord and self.octave_boxes[0].currentIndex()!=1:self.octave_boxes[0].setCurrentIndex(1)
 def step_melody_octave(self,delta):
  box=self.octave_boxes[1];box.setCurrentIndex(max(0,min(2,box.currentIndex()+delta)))
  self.engine.status='右手档位：'+box.currentText()
 def pose_heartbeat(self):
  e=self.engine
  self.keyboard_jobs={jid for jid in self.keyboard_jobs if self.controller.job(jid)['state'] not in ('completed','failed','cancelled')}
  if not self.keyboard_jobs and self.controller.active is None and self.isActiveWindow() and e.ready and e.instrument_state.get('mode')==1 and e.duo.get('running') and self.controller.queue.qsize()<2:
   for h in range(2):self.send_keys(h)
 def keyboard_profile(self,h):
  profiles=self.engine.duo_config.get('profiles',[])
  return profiles[h] if self.engine.ready and len(profiles)==2 and profiles[h] in (0,1,2) else self.profile.currentIndex()
 def keyboard_allowed(self):
  focus=W.QApplication.focusWidget()
  editable=isinstance(focus,(W.QLineEdit,W.QTextEdit,W.QPlainTextEdit,W.QAbstractSpinBox,W.QComboBox))
  return self.keyboard_enabled.isChecked() and self.isActiveWindow() and self.tabs.currentIndex()==0 and self.engine.ready and self.engine.instrument_state.get('mode')==1 and self.engine.duo.get('running',False) and not editable
 def release_keyboard(self):
  self.keyboard_down.clear();self.lesson_keys_down.clear()
  for h in range(2):
   if self.key_masks[h]&2:
    self.key_masks[h]&=1
    if self.engine.ready:self.send_keys(h)
 def keyboard_hit(self,h,velocity):
  z=self.mouse_zones[h]
  if z is None:self.engine.status='请先用鼠标选择该手音区';return
  job=self.safe(lambda:self.submit_command('keys33.strike',dict(hand=h,zone=z,profile=self.keyboard_profile(h),pitch=self.pitch_values[h],velocity=velocity,expression=bool(self.key_masks[h]&2),slide=bool(self.key_masks[h]&2) and self.glide.isChecked())))
  if job:self.keyboard_jobs.add(job['id'])
 def lesson_keyboard_event(self,event):
  key=event.key();pad=bool(event.modifiers()&C.Qt.KeyboardModifier.KeypadModifier);token=(key,pad)
  if event.type()==C.QEvent.Type.KeyRelease and token in self.lesson_keys_down:
   if not event.isAutoRepeat():self.lesson_keys_down.discard(token)
   return True
  if self.tabs.currentIndex()!=3:return False
  focus=W.QApplication.focusWidget()
  if not self.isActiveWindow() or isinstance(focus,(W.QLineEdit,W.QTextEdit,W.QPlainTextEdit,W.QAbstractSpinBox,W.QComboBox)):return False
  if event.modifiers()&(C.Qt.KeyboardModifier.ControlModifier|C.Qt.KeyboardModifier.AltModifier|C.Qt.KeyboardModifier.MetaModifier):return False
  if not ord('1')<=key<=ord('7'):return False
  if event.type()==C.QEvent.Type.KeyPress and not event.isAutoRepeat() and token not in self.lesson_keys_down:
   self.lesson_keys_down.add(token);lab_score_ui.answer(self,int(pad),key-ord('1'))
  return True
 def eventFilter(self,obj,event):
  if event.type() not in (C.QEvent.Type.KeyPress,C.QEvent.Type.KeyRelease):return super().eventFilter(obj,event)
  if self.lesson_keyboard_event(event):return True
  key=event.key();keypad=bool(event.modifiers()&C.Qt.KeyboardModifier.KeypadModifier);token=(key,keypad)
  mapping={ord('W'):(0,48),ord('S'):(0,48),ord('O'):(1,48),ord('L'):(1,48),ord('A'):(0,0),ord('K'):(1,0)}
  if event.type()==C.QEvent.Type.KeyRelease and token in self.keyboard_down:
   if not event.isAutoRepeat():
    self.keyboard_down.discard(token)
    if not keypad and key in (ord('A'),ord('K')):self.key_change(mapping[key][0],1,False)
   return True
  if not self.keyboard_allowed() or event.modifiers()&(C.Qt.KeyboardModifier.ControlModifier|C.Qt.KeyboardModifier.AltModifier|C.Qt.KeyboardModifier.MetaModifier):return super().eventFilter(obj,event)
  press=event.type()==C.QEvent.Type.KeyPress and not event.isAutoRepeat() and token not in self.keyboard_down
  if key==C.Qt.Key.Key_Space:
   if press:self.release_keyboard();self.submit_command('duo.stop')
   return True
  if self.input_mode.currentIndex()==1:
   if ord('1')<=key<=ord('7'):
    if press:
     self.keyboard_down.add(token);h=int(keypad);z=key-ord('1')
     if self.keyboard_profile(h)!=0:self.engine.status='数字演奏请先应用七音布局';return True
     self.mouse_zones[h]=z;self.fans[h].hover=z;self.fans[h].update()
     if h==0 and self.engine.duo_config.get('chord'):self.octave_boxes[0].setCurrentIndex(1)
     self.keyboard_hit(h,48)
    return True
   if not keypad and key in (ord('W'),ord('S')):
    if press:self.keyboard_down.add(token);self.step_melody_octave(1 if key==ord('W') else -1)
    return True
   if keypad or key not in (ord('A'),ord('K')):return super().eventFilter(obj,event)
  if key not in mapping or keypad:return super().eventFilter(obj,event)
  if press:
   self.keyboard_down.add(token);h,velocity=mapping[key]
   if velocity:self.keyboard_hit(h,velocity)
   else:self.expression_at[h]=time.monotonic();self.key_change(h,1,True)
  return True
 def changeEvent(self,event):
  if event.type()==C.QEvent.Type.ActivationChange and not self.isActiveWindow():
   self.release_keyboard()
   if self.engine.ready and self.engine.instrument_state.get('mode')==1:self.safe(lambda:self.submit_command('duo.stop'))
  super().changeEvent(event)
 def closeEvent(self,event):
  W.QApplication.instance().removeEventFilter(self)
  self.release_keyboard();self.timer.stop();self.pose_timer.stop()
  if getattr(self,'score_worker',None):self.score_worker.cancel()
  self.engine.close();self.controller.closed.set();event.accept()
if __name__=='__main__':
 app=W.QApplication(sys.argv);app.setApplicationName('TangLab');chinese_qt(app);window=Window();window.show()
 if '--keyboard-smoke' in sys.argv:
  from lab_keyboard_smoke import start
  start(window,app,sys.argv[sys.argv.index('--keyboard-smoke')+1]);sys.exit(0)
 if '--score-conversion-smoke' in sys.argv:
  from lab_score_conversion_smoke import start
  start(window,app,sys.argv[sys.argv.index('--score-conversion-smoke')+1])
 sys.exit(app.exec())
