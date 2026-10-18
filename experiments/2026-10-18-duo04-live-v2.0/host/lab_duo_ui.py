"""Chinese mouse fans and real DUO02 capture/status views."""
import math,time,json,sys
from pathlib import Path
import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore as C,QtGui as G,QtWidgets as W
from lab_duo import PROFILES,NAMES,PRESETS,CHANNELS as DUO_CHANNELS,note_map
from lab_ui import CHANNELS,ChineseViewBox,setup_plot,spectrum

class MouseFan(W.QWidget):
    selected=C.Signal(object)
    struck=C.Signal(int)
    def __init__(self,hand,parent=None):
        super().__init__(parent);self.hand=hand;self.profile=0;self.hover=None;self.confirmed=None;self.hit=None;self.hit_at=0
        self.setMouseTracking(True);self.setMinimumSize(280,155)
        self.setToolTip('移动鼠标预选音区，左键每按下一次击发一次；双击两次，按住不连发。离开扇区清除预选。')
    def geometry_values(self):
        return self.width()/2,self.height()-30,min(self.width()*.47,self.height()-70)
    def zone_at(self,x,y):
        cx,cy,r=self.geometry_values();dx=x-cx;dy=cy-y;distance=math.hypot(dx,dy)
        if dy<0 or not r*.30<=distance<=r:return None
        angle=math.degrees(math.atan2(dx,dy));n=len(PROFILES[self.profile])
        return min(n-1,max(0,int((angle+90)*n/180)))
    def mouseMoveEvent(self,e):
        z=self.zone_at(e.position().x(),e.position().y())
        if z!=self.hover:self.hover=z;self.selected.emit(z);self.update()
    def leaveEvent(self,e):
        if self.hover is not None:self.hover=None;self.selected.emit(None);self.update()
    def press(self,e):
        if e.button()!=C.Qt.MouseButton.LeftButton:return
        z=self.zone_at(e.position().x(),e.position().y())
        if z is not None:self.hover=z;self.selected.emit(z);self.struck.emit(z)
    def mousePressEvent(self,e):self.press(e)
    def mouseDoubleClickEvent(self,e):self.press(e)
    def paintEvent(self,e):
        p=G.QPainter(self);p.setRenderHint(G.QPainter.RenderHint.Antialiasing)
        cx,cy,r=self.geometry_values();inner=r*.30;n=len(PROFILES[self.profile]);step=180/n
        font=p.font();font.setPointSize(10);p.setFont(font)
        for z in range(n):
            start=180-z*step;end=start-step
            path=G.QPainterPath();a=math.radians(start)
            path.moveTo(cx+inner*math.cos(a),cy-inner*math.sin(a));path.lineTo(cx+r*math.cos(a),cy-r*math.sin(a))
            path.arcTo(C.QRectF(cx-r,cy-r,2*r,2*r),start,-step)
            a=math.radians(end);path.lineTo(cx+inner*math.cos(a),cy-inner*math.sin(a));path.arcTo(C.QRectF(cx-inner,cy-inner,2*inner,2*inner),end,step);path.closeSubpath()
            color='#15364b'
            if z==self.hover:color='#245775'
            if z==self.confirmed:color='#087c85'
            if z==self.hit and time.monotonic()-self.hit_at<.45:color='#ad286d'
            p.fillPath(path,G.QColor(color));p.setPen(G.QPen(G.QColor('#638899'),1));p.drawPath(path)
            a=math.radians(start-step/2);x=cx+math.cos(a)*r*.70;y=cy-math.sin(a)*r*.70
            p.setPen(G.QColor('#edf5ff'));p.drawText(C.QRectF(x-24,y-12,48,24),C.Qt.AlignmentFlag.AlignCenter,NAMES[self.profile][z])
        p.setPen(G.QColor('#9cb6cb'));p.drawText(C.QRectF(0,self.height()-24,self.width(),24),C.Qt.AlignmentFlag.AlignCenter,
            ('左手 → 左声道' if self.hand==0 else '右手 → 右声道')+' · 青色：板上预选 / 品红：已接受击发')

from lab_monitor_ui import MonitorGuiMixin

class DuoGuiMixin(MonitorGuiMixin):
    def duo_page(self):
        layout=self.page('08  鼠标音区测试');self.duo_page_index=self.tabs.count()-1
        self.duo_intro=label=W.QLabel('DUO02-MOUSE 专用测试：无需 IMU；鼠标选择，FPGA 真实合成，HDMI 同步。连接后默认静音。');label.setWordWrap(True);layout.addWidget(label)
        from lab_instrument import build_controls
        build_controls(self,layout)
        row=W.QHBoxLayout();self.duo_start_button=self.button(row,'开始鼠标测试',lambda:self.apply_duo(True))
        self.button(row,'停止鼠标测试',self.stop_duo);self.button(row,'鼠标模式模拟',lambda:self.submit_command('duo.demo'));self.button(row,'四音色脱机模拟',lambda:self.submit_command('instrument.demo'))
        self.button(row,'应用音区参数',lambda:self.apply_duo(None));self.duo_sync=W.QCheckBox('击发同步抓取 512 点');self.duo_sync.setChecked(True);row.addWidget(self.duo_sync)
        self.duo_pause=W.QCheckBox('暂停绘图');self.duo_pause.toggled.connect(self.pause.setChecked);self.pause.toggled.connect(self.duo_pause.setChecked);row.addWidget(self.duo_pause);layout.addLayout(row)
        self.duo_config_job=None;self.duo_last_job=None;self.duo_last_event=0;self.duo_capture_requested=False;self.duo_seen_hits=[0,0]
        self.duo_last_draw=None;self.duo_channel_key=None;self.duo_select_pending={};self.duo_select_jobs={};self.duo_select_sent={};self.duo_config_dirty=False
        row=W.QHBoxLayout();self.duo_expression=[];self.duo_fans=[];self.duo_profiles=[];self.duo_presets=[];self.duo_octaves=[];self.duo_velocities=[];self.duo_holds=[];self.duo_releases=[];self.duo_piano_holds=[];self.duo_piano_decays=[]
        for hand in (0,1):
            box=W.QGroupBox('左手' if hand==0 else '右手');col=W.QVBoxLayout(box);opts=W.QGridLayout()
            profile=W.QComboBox();profile.addItems(['七音区','五音区','十二音区']);opts.addWidget(profile,0,0)
            preset=W.QComboBox();preset.addItems(PRESETS);opts.addWidget(preset,0,1)
            octave=W.QComboBox();octave.addItems(['低两组 C2','低一组 C3','标准 C4','高一组 C5']);octave.setCurrentIndex(2);opts.addWidget(octave,1,0)
            velocity=W.QSpinBox();velocity.setRange(1,127);velocity.setValue(96);velocity.setPrefix('力度 ');opts.addWidget(velocity,1,1)
            col.addLayout(opts);timing=W.QHBoxLayout()
            hold=W.QDoubleSpinBox();hold.setRange(.1,5);hold.setSingleStep(.1);hold.setDecimals(1);hold.setValue(1.5);hold.setPrefix('按键保持 ');hold.setSuffix(' 秒');timing.addWidget(hold)
            release=W.QComboBox();release.addItems(['释音 0.2 秒','释音 0.5 秒','释音 1.5 秒']);release.setCurrentIndex(1);timing.addWidget(release);col.addLayout(timing)
            hold.setToolTip('鼠标击发后保持按键的时间；管乐便于测试持续复音，拨弦和铃音仍会自然衰减。需要DUO02-MOUSE 1.1。')
            hold.valueChanged.connect(self.duo_edited);release.currentIndexChanged.connect(self.duo_edited)
            self.duo_holds.append(hold);self.duo_releases.append(release)
            timing=W.QHBoxLayout();ph=W.QCheckBox('钢琴主体保持');pd=W.QDoubleSpinBox();pd.setRange(.2,30);pd.setDecimals(1);pd.setValue(6);pd.setSuffix(' 秒');pd.setPrefix('至10% ')
            ph.toggled.connect(self.duo_edited);pd.valueChanged.connect(self.duo_edited);timing.addWidget(ph);timing.addWidget(pd);col.addLayout(timing)
            ph.setToolTip('仅钢琴：按键保持期间主体不自然衰减，松键后仍按释音收音。非采样钢琴。');pd.setToolTip('仅钢琴的自然衰减时间，与按键保持和松键后的释音时间不同。')
            self.duo_piano_holds.append(ph);self.duo_piano_decays.append(pd)
            expr=W.QGridLayout();vib=W.QCheckBox('颤音');rate=W.QDoubleSpinBox();rate.setRange(.1,12);rate.setValue(5.5);rate.setSuffix(' Hz')
            depth=W.QSpinBox();depth.setRange(0,100);depth.setValue(20);depth.setSuffix(' 音分')
            glide=W.QCheckBox('滑音');duration=W.QSpinBox();duration.setRange(10,2000);duration.setValue(150);duration.setSuffix(' ms')
            expr.addWidget(vib,0,0);expr.addWidget(rate,0,1);expr.addWidget(depth,0,2);expr.addWidget(glide,1,0);expr.addWidget(duration,1,1,1,2);col.addLayout(expr)
            glide.setToolTip('可选，默认关闭。同手新音从前一个音高滑向目标；前音约5ms收音。关闭恢复复音；左和弦模式左手不滑音，右手仍可使用。')
            vib.setToolTip('主动音高颤音，速率0.1～12Hz，深度0～100音分；与音效合唱、异常抖动不同。须应用音区参数。')
            for widget in (vib,rate,depth,glide,duration):
                (widget.toggled if isinstance(widget,W.QCheckBox) else widget.valueChanged).connect(self.duo_edited)
            self.duo_expression.append((vib,rate,depth,glide,duration))
            fan=MouseFan(hand);col.addWidget(fan,1);row.addWidget(box,1)
            profile.currentIndexChanged.connect(lambda index,h=hand:self.duo_profile_changed(h,index))
            preset.currentIndexChanged.connect(self.duo_edited)
            fan.selected.connect(lambda z,h=hand:self.select_duo(h,z));fan.struck.connect(lambda z,h=hand:self.strike_duo(h,z))
            self.duo_profiles.append(profile);self.duo_presets.append(preset);self.duo_octaves.append(octave);self.duo_velocities.append(velocity);self.duo_fans.append(fan)
        layout.addLayout(row,3)
        row=W.QHBoxLayout();self.duo_chord=W.QCheckBox('左和弦 / 右旋律');row.addWidget(self.duo_chord)
        self.duo_effect=W.QComboBox();self.duo_effect.addItems(['音效旁路','延迟','合唱','简化混响']);row.addWidget(self.duo_effect)
        self.duo_wet=W.QSpinBox();self.duo_wet.setRange(0,255);self.duo_wet.setValue(128);self.duo_wet.setPrefix('湿声 /256：');row.addWidget(self.duo_wet)
        self.duo_volume=W.QSpinBox();self.duo_volume.setRange(0,64);self.duo_volume.setValue(32);self.duo_volume.setPrefix('总音量（0～64）：');self.duo_volume.setSuffix(' /256');row.addWidget(self.duo_volume)
        self.duo_volume.setToolTip('256表示当前处理链路的100%。1.2含响度补偿与限幅，同一数值比旧版响；默认32。1.1允许0～256，1.0只支持0～64。')
        self.button(row,'导出本次鼠标采样',self.export_audio);layout.addLayout(row)
        row=W.QHBoxLayout();self.button(row,'选择配套鼠标工程',self.choose_duo_project);row.addStretch();layout.addLayout(row)
        for widget in (self.duo_chord,self.duo_effect,self.duo_wet,self.duo_volume):
            signal=widget.toggled if isinstance(widget,W.QCheckBox) else widget.currentIndexChanged if isinstance(widget,W.QComboBox) else widget.valueChanged
            signal.connect(self.duo_edited)
        self.duo_feedback=W.QLabel('请下载 DUO02-MOUSE 配套固件，或点击鼠标模式模拟。');self.duo_feedback.setWordWrap(True);layout.addWidget(self.duo_feedback)
        self.duo_status_text=W.QLabel('板上状态待连接');self.duo_status_text.setWordWrap(True);layout.addWidget(self.duo_status_text)
        self.duo_scope=pg.PlotWidget(title='最近完整采样：效果后左右声道',viewBox=ChineseViewBox());setup_plot(self.duo_scope)
        self.duo_scope.setBackground('#111c2c');self.duo_scope.setLabel('bottom','时间','ms');self.duo_scope.setLabel('left','幅值','PCM');self.duo_scope.addLegend()
        self.duo_scope_lines=[self.duo_scope.plot(pen=color,name=name) for color,name in [('#53dfc2','效果后左'),('#79abff','效果后右')]];layout.addWidget(self.duo_scope,1)
        self.duo_fft=pg.PlotWidget(title='效果后混音 FFT · 完整单段 / 汉宁窗',viewBox=ChineseViewBox());setup_plot(self.duo_fft);self.duo_fft.setBackground('#111c2c')
        self.duo_fft.setLabel('bottom','频率','Hz');self.duo_fft.setLabel('left','幅度','dBFS');self.duo_fft_line=self.duo_fft.plot(pen='#53dfc2');layout.addWidget(self.duo_fft,1)
        self.init_monitor_ui(layout)
        self.duo_timer=C.QTimer(self);self.duo_timer.timeout.connect(self.refresh_duo);self.duo_timer.start(33)
    def duo_edited(self,*args):self.duo_config_dirty=True
    def choose_duo_project(self):
        root=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
        choices=[root/'duo02-mouse-1.4-20261017/tanglab_duo02_mouse.gprj',root/'fpga/duo02-mouse/tanglab_duo02_mouse.gprj',root/'duo02-mouse-20261017/tanglab_duo02_mouse.gprj']
        project=next((p for p in choices if p.is_file()),None)
        if project is None:raise ValueError('配套工程缺失，请解压完整分享包')
        self.project.setText(str(project));self.duo_feedback.setText('已选择配套工程，可在“05 Gowin 工程”查看或编译；下载仍使用官方Programmer。')
    def duo_profile_changed(self,h,index):
        self.duo_fans[h].profile=index;self.duo_fans[h].hover=None;self.duo_fans[h].confirmed=None;self.duo_fans[h].update();self.duo_edited()
    def duo_settings(self,run):
        p=dict(run=run,profiles=[x.currentIndex() for x in self.duo_profiles],presets=[x.currentIndex() for x in self.duo_presets],
                    chord=self.duo_chord.isChecked(),effect=self.duo_effect.currentIndex(),wet=self.duo_wet.value(),gain=self.duo_volume.value())
        if self.engine.capabilities.get('duo_extended'):p.update(hold_ms=[round(x.value()*1000) for x in self.duo_holds],release_ids=[x.currentIndex() for x in self.duo_releases])
        if self.engine.capabilities.get('duo_quality'):p.update(piano_hold=[x.isChecked() for x in self.duo_piano_holds],piano_decay_s=[x.value() for x in self.duo_piano_decays])
        if self.engine.capabilities.get('duo_expression'):
            p['expression']=dict(hands=[dict(vibrato=v.isChecked(),vibrato_hz=r.value(),vibrato_cents=d.value(),glide=g.isChecked(),glide_ms=t.value()) for v,r,d,g,t in self.duo_expression])
        return p
    def apply_duo(self,run):
        if self.duo_config_job and self.controller.job(self.duo_config_job)['state'] not in ('completed','failed','cancelled'):raise ValueError('正在等待参数应答，请稍候')
        run=self.engine.duo_config['run'] if run is None else run
        j=self.submit_command('duo.configure',self.duo_settings(run));
        if run and self.engine.capabilities.get('duo_monitor') and self.monitor_mode.currentIndex()==0:self.monitor_auto_job=j['id']
        self.duo_config_job=j['id'];self.duo_last_job=j['id'];self.duo_config_dirty=False
    def stop_duo(self):
        self.duo_select_pending.clear()
        if self.engine.ready and self.engine.capabilities.get('duo_mouse'):
            j=self.submit_command('duo.stop');self.duo_last_job=j['id']
    def select_duo(self,hand,zone):
        self.duo_select_pending[hand]=dict(hand=hand,valid=zone is not None,zone=zone or 0)
    def strike_duo(self,hand,zone):
        if self.duo_config_dirty:
            self.duo_feedback.setText('参数有修改，请先点击“应用音区参数”。');return
        if self.duo_config_job and self.controller.job(self.duo_config_job)['state'] not in ('completed','failed','cancelled'):
            self.duo_feedback.setText('正在等待音区参数应答，暂不接受新击发。');return
        try:
            p=dict(hand=hand,zone=zone,profile=self.duo_profiles[hand].currentIndex(),octave=self.duo_octaves[hand].currentIndex()-2,
                   velocity=self.duo_velocities[hand].value(),capture=self.duo_sync.isChecked())
            j=self.submit_command('duo.strike',p);self.duo_last_job=j['id'];self.duo_capture_requested=p['capture']
        except Exception as exc:self.duo_feedback.setText('击发未提交：'+str(exc))
    def sync_duo_labels(self):
        names=self.engine.channel_names
        if tuple(names)==self.duo_channel_key:return
        self.duo_channel_key=tuple(names);CHANNELS[:]=names
        for combo in (self.cursor_channel,self.spectrum_channel):
            with C.QSignalBlocker(combo):
                for i,name in enumerate(names):combo.setItemText(i,name)
        for plot in self.plots:
            if plot.legend:plot.legend.clear()
        for i,curve in enumerate(self.curves):
            curve.opts['name']=names[i];plot=self.plots[i if self.stacked.isChecked() else 0]
            if plot.legend:plot.legend.addItem(curve,names[i])
        self.spectrum_key=None;self.revision=-1
    def refresh_duo(self):
        self.refresh_monitor()
        e=self.engine;self.sync_duo_labels();supported=e.capabilities.get('duo_mouse',False)
        for group in self.duo_expression:
            for widget in group:widget.setEnabled(e.ready and e.capabilities.get('duo_expression',False))
        extended=e.capabilities.get('duo_extended',False);maximum=256 if extended else 64
        if self.duo_volume.maximum()!=maximum:
            with C.QSignalBlocker(self.duo_volume):self.duo_volume.setMaximum(maximum)
        self.duo_volume.setPrefix(f'总音量（0～{maximum}）：')
        for widget in self.duo_holds:widget.setMaximum(10.0 if e.capabilities.get('instrument') else 5.0)
        for widget in self.duo_piano_decays:
            widget.setPrefix('C4至10% ' if e.capabilities.get('instrument') else '至10% ')
            widget.setToolTip('钢琴C4参考自然衰减；低于C3约慢4/3倍，C5及以上约快1/3。它不等于按键保持时长，也不改变到点松键。' if e.capabilities.get('instrument') else '钢琴主体自然衰减到10%的参考时间。')
        for widget in self.duo_holds+self.duo_releases:widget.setEnabled(supported and extended)
        quality=e.capabilities.get('duo_quality',False)
        from lab_instrument import refresh_controls
        refresh_controls(self)
        self.duo_intro.setText('DUO04：双IMU脱机 / 逐音教学 / 电脑鼠标调试共用板上合成；保持时长从实际起音计时。' if e.capabilities.get('instrument') else 'DUO02-MOUSE专用测试：无需IMU；鼠标选择，FPGA实时合成。')
        for h,combo in enumerate(self.duo_presets):
            names=e.capabilities.get('timbre_names',PRESETS)
            if [combo.itemText(i) for i in range(combo.count())]!=names:
                old=combo.currentIndex()
                with C.QSignalBlocker(combo):combo.clear();combo.addItems(names);combo.setCurrentIndex(min(old,len(names)-1))
            for i in (4,5):
                if combo.model().item(i) is not None:combo.model().item(i).setEnabled(supported and quality)
            for widget in (self.duo_piano_holds[h],self.duo_piano_decays[h]):widget.setEnabled(supported and quality)
        if getattr(self,'duo_session',None) is not e.audio_session:
            self.duo_session=e.audio_session;self.duo_select_sent.clear();self.duo_select_jobs.clear();self.duo_seen_hits=[0,0]
        for attr in ('duo_last_job','duo_config_job'):
            if getattr(self,attr) not in self.controller.jobs:setattr(self,attr,None)
        self.duo_select_jobs={h:j for h,j in self.duo_select_jobs.items() if j in self.controller.jobs}
        self.duo_start_button.setEnabled(supported and e.ready)
        self.table.setEnabled(not supported)
        for b in self.findChildren(W.QPushButton):
            if b.text() in ('应用四个声部','全部松键 / 释音','设置接口并复位 IMU','应用报告配置','开启包络预览'):b.setEnabled(not supported)
        self.trigger.model().item(1).setEnabled(not supported)
        if supported and self.trigger.currentIndex()!=0:self.trigger.setCurrentIndex(0)
        if not supported:return
        if not self.duo_last_job:self.duo_feedback.setText('鼠标模式已就绪；点击开始鼠标测试，再点击音区击发。' if not e.duo.get('running') else '测试已开启；移动预选，左键击发。')
        if e.ready and not self.duo_config_dirty:
            for h,p in list(self.duo_select_pending.items()):
                old=self.duo_select_jobs.get(h)
                if old and self.controller.job(old)['state'] not in ('completed','failed','cancelled'):continue
                if p!=self.duo_select_sent.get(h):
                    try:self.duo_select_jobs[h]=self.submit_command('duo.select',p)['id'];self.duo_select_sent[h]=p
                    except Exception as exc:self.duo_feedback.setText('预选未提交：'+str(exc))
                self.duo_select_pending.pop(h,None)
        s=e.duo_snapshot()
        for h,fan in enumerate(self.duo_fans):
            fan.confirmed=s['selected'][h] if self.duo_profiles[h].currentIndex()==s['profiles'][h] else None
            if s['hits'][h]!=self.duo_seen_hits[h]:fan.hit=s.get('last_zones',[fan.hover,fan.hover])[h];fan.hit_at=time.monotonic();self.duo_seen_hits[h]=s['hits'][h]
            fan.update()
        if self.duo_last_job:
            j=self.controller.job(self.duo_last_job);text={'queued':'已排队','running':'已发送／等待应答','acknowledged':'设备已应答','completed':'设备已接受','failed':'失败','cancelled':'已取消','simulated':'模拟已接受（非设备应答）'}.get(j['state'],j['state'])
            if j['state']=='completed' and j['action']=='duo.strike':
                self.duo_last_event=j['result']['event_id'];text+=f"：击发 {self.duo_last_event}，音符 {j['result']['notes']}"
                if self.duo_capture_requested:
                    if e.audio_metadata.get('event_id')==self.duo_last_event:text+='；采样已完整收到'
                    elif s['event_id']==self.duo_last_event and s['capture_event_id']!=self.duo_last_event:text+='；采样缓冲忙，本次仅发声'
                    else:text+='；等待同步采样'
            elif j['state'] in ('failed','cancelled'):text+='：'+j['message']
            self.duo_feedback.setText(text+(' · 当前参数尚未应用' if self.duo_config_dirty else ''))
        active=[i+1 for i in range(32) if s['active_mask']>>i&1]
        stops={0:'正常',1:'已停止',2:'通信超时，已停止',3:'KEY2静音，需重新开始'}
        self.duo_status_text.setText(f"{e.source} | 板上：{'校准正弦持续发声' if e.sine_state.get('enabled') else '测试中' if s['running'] else '静音'} | {stops.get(s['stop_reason'],'待确认')}\n"
            f"左右击发 {s['hits'][0]} / {s['hits'][1]} · 活动声部 {len(active)}/32：{active}\n"
            f"CRC {e.parser.errors} / 缺包 {e.gaps} · 板上事件丢弃 {s.get('event_drops',0)} · 欠载 {s.get('underflows',0)} · 同步抓取未执行 {s['capture_skipped']}")
        key=(e.audio_session,e.audio_revision)
        if not e.capabilities.get('duo_monitor') and not self.pause.isChecked() and not self.clear_pending and e.audio is not None and key!=self.duo_last_draw:
            with e.lock:a=e.audio.copy();fs=e.fs;metadata=dict(e.audio_metadata)
            for c,line in enumerate(self.duo_scope_lines):line.setData(np.arange(len(a))/fs*1000,a[:,c+2])
            f,db,_=spectrum(a[:,4],fs);self.duo_fft_line.setData(f,db);self.duo_fft.setXRange(0,5000)
            self.duo_scope.setTitle(f"效果后左右 · {len(a)} 点 / {fs} Hz · 击发 {metadata.get('event_id',0)} · 板上tick {metadata.get('board_tick','—')}")
            self.duo_last_draw=key
        if e.audio is None and not self.pause.isChecked():
            for line in self.duo_scope_lines:line.setData([],[])
            self.duo_fft_line.setData([],[]);self.duo_last_draw=None
    def changeEvent(self,event):
        if event.type()==C.QEvent.Type.ActivationChange and hasattr(self,'duo_last_job'):
            C.QTimer.singleShot(30,self.check_external_focus)
        super().changeEvent(event)
