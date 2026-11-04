"""Shared dock scope, 32-voice selection, independent persistent sine UI."""
import json,time,csv
from pathlib import Path
import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore as C,QtWidgets as W
from lab_ui import ChineseViewBox,setup_plot,spectrum

class MonitorGuiMixin:
    def init_monitor_ui(self,layout):
        box=W.QGroupBox('独立单正弦底噪测试（非32声部演奏；绕过音色、音效与响度补偿）');row=W.QHBoxLayout(box)
        self.sine_frequency=W.QDoubleSpinBox();self.sine_frequency.setRange(20,10000);self.sine_frequency.setValue(1000);self.sine_frequency.setSuffix(' Hz');row.addWidget(self.sine_frequency)
        self.sine_level=W.QDoubleSpinBox();self.sine_level.setRange(-60,-6);self.sine_level.setValue(-30);self.sine_level.setSuffix(' dBFS');row.addWidget(self.sine_level)
        self.sine_channels=W.QComboBox();self.sine_channels.addItems(['左声道','右声道','双声道']);self.sine_channels.setCurrentIndex(2);row.addWidget(self.sine_channels)
        self.sine_start_button=self.button(row,'开始持续正弦',self.start_sine)
        self.sine_stop_button=self.button(row,'停止正弦',self.stop_sine)
        box.setToolTip('先从−30dBFS和较低耳机音量开始；总音量不作用于此校准源。约5ms渐变启停；停止后保持静音。数值为数字峰值，不能替代模拟底噪仪器测量。')
        layout.addWidget(box)
        grid=W.QGridLayout();self.voice_tiles=[];self.monitor_selection=[0,16];self.monitor_job=None;self.monitor_auto_job=None
        for i in range(32):
            b=W.QPushButton();b.setCheckable(True);b.setChecked(i in self.monitor_selection);b.setMinimumHeight(35);b.setSizePolicy(W.QSizePolicy.Policy.Ignored,W.QSizePolicy.Policy.Preferred)
            b.setToolTip(f'声部{i+1}：'+('左手' if i<16 else '右手')+'；点击选择真实板内PCM，最多4路。活动状态和包络来自板上状态包。')
            b.clicked.connect(lambda checked,n=i:self.select_monitor_voice(n,checked));grid.addWidget(b,i//8,i%8);self.voice_tiles.append(b)
        self.monitor_tile_grid=grid
        self.monitor_selection_label=W.QLabel('默认监测声部1、17；最多4路。采样选路从下一次抓取生效。');self.monitor_selection_label.setWordWrap(True)
        self.monitor_dock=W.QDockWidget('实时波形与32声部监测',self);self.monitor_dock.setObjectName('shared-monitor');self.monitor_dock.setAllowedAreas(C.Qt.DockWidgetArea.AllDockWidgetAreas)
        content=W.QWidget();col=W.QVBoxLayout(content);controls=W.QHBoxLayout()
        self.monitor_mode=W.QComboBox();self.monitor_mode.addItems(['连续监测','击发同步抓取']);controls.addWidget(self.monitor_mode)
        self.monitor_mode.currentIndexChanged.connect(self.monitor_mode_changed)
        self.monitor_live_button=self.button(controls,'开始监测',self.toggle_monitor_live)
        size=W.QComboBox();size.addItems(['512点','2048点']);size.currentIndexChanged.connect(self.capture_size.setCurrentIndex);self.capture_size.currentIndexChanged.connect(size.setCurrentIndex);controls.addWidget(size)
        self.monitor_pause=W.QCheckBox('暂停');self.monitor_pause.toggled.connect(self.pause.setChecked);self.pause.toggled.connect(self.monitor_pause.setChecked);controls.addWidget(self.monitor_pause);col.addLayout(controls)
        controls=W.QHBoxLayout();view=W.QComboBox();view.addItems(['最新一段','滚动历史']);view.currentIndexChanged.connect(self.live_view.setCurrentIndex);self.live_view.currentIndexChanged.connect(view.setCurrentIndex);controls.addWidget(view)
        follow=W.QCheckBox('跟随最新');follow.setChecked(True);follow.toggled.connect(self.follow_latest.setChecked);self.follow_latest.toggled.connect(follow.setChecked);controls.addWidget(follow)
        self.button(controls,'导出',self.export_monitor);self.button(controls,'恢复缩放',self.reset_monitor_zoom);col.addLayout(controls)
        self.monitor_note=W.QLabel('分段采集，段间有空档；等待完整数据');self.monitor_note.setWordWrap(True);col.addWidget(self.monitor_note)
        col.addWidget(W.QLabel('1～16左手，17～32右手；编号:音符／包络百分比；勾选最多4路PCM'))
        col.addLayout(self.monitor_tile_grid);col.addWidget(self.monitor_selection_label)
        scroll=W.QScrollArea();scroll.setWidgetResizable(True);plots=W.QWidget();self.monitor_plot_layout=W.QVBoxLayout(plots);scroll.setWidget(plots);col.addWidget(scroll,1)
        self.monitor_voice_plots=[];self.monitor_voice_lines=[];self.monitor_plot_ids=None;self.monitor_zoomed=None
        for i in range(4):
            plot=pg.PlotWidget(viewBox=ChineseViewBox());setup_plot(plot);plot.setBackground('#111c2c');plot.setMinimumHeight(140)
            plot.setLabel('bottom','时间','ms');plot.setLabel('left','幅值','PCM');plot.getAxis('left').enableAutoSIPrefix(False);plot.getAxis('bottom').enableAutoSIPrefix(False);line=plot.plot(pen=['#53dfc2','#79abff','#ffbd69','#e78cda'][i])
            self.monitor_plot_layout.addWidget(plot);self.monitor_voice_plots.append(plot);self.monitor_voice_lines.append(line)
        # Reparent existing page08 stereo and spectrum into a shared dock.
        for plot in (self.duo_scope,self.duo_fft):
            plot.getAxis('left').enableAutoSIPrefix(False);plot.getAxis('bottom').enableAutoSIPrefix(False)
            layout.removeWidget(plot);plot.setMinimumHeight(160);self.monitor_plot_layout.addWidget(plot)
        self.monitor_all_plots=self.monitor_voice_plots+[self.duo_scope,self.duo_fft]
        self.monitor_cursors=[]
        for plot in self.monitor_all_plots:
            vb=plot.getViewBox();vb.selected.connect(lambda p=plot:self.enlarge_monitor(p));vb.sigRangeChangedManually.connect(lambda *_:self.follow_latest.setChecked(False))
            lines=[]
            for k,pos in enumerate([2.,6.,-1000.,1000.]):
                line=pg.InfiniteLine(pos=pos,angle=90 if k<2 else 0,movable=True,pen='#ffd166' if k<2 else '#e78cda',label='{value:.2f}')
                plot.addItem(line,ignoreBounds=True);line.hide();lines.append(line)
                line.sigPositionChanged.connect(self.monitor_cursor_readout)
            self.monitor_cursors.append(lines)
            def menu(m,p=plot,ls=lines):
                for label,group in ([('时间游标',ls[:2]),('幅值游标',ls[2:])] if p is not self.duo_fft else []):
                    action=m.addAction(label);action.setCheckable(True);action.setChecked(group[0].isVisible());action.toggled.connect(lambda on,g=group:[x.setVisible(on) for x in g])
                m.addAction('恢复全部波形',lambda:self.enlarge_monitor(None))
            vb.cursor_menu=menu
        self.monitor_readout=W.QLabel('右键可开启独立时间／幅值游标；单击波形放大，再次单击恢复。');self.monitor_readout.setWordWrap(True);col.addWidget(self.monitor_readout)
        self.monitor_dock.setWidget(content);self.addDockWidget(C.Qt.DockWidgetArea.RightDockWidgetArea,self.monitor_dock);self.monitor_dock.setMinimumWidth(440);self.resizeDocks([self.monitor_dock],[520],C.Qt.Orientation.Horizontal)
        self.monitor_render_key=None;self.monitor_ui_supported=None
        W.QApplication.instance().applicationStateChanged.connect(lambda *_:C.QTimer.singleShot(30,self.check_external_focus))
        self.follow_latest.toggled.connect(lambda *_:setattr(self,'monitor_render_key',None))
        page=self.tabs.widget(self.duo_page_index);self.tabs.removeTab(self.duo_page_index)
        page_scroll=W.QScrollArea();page_scroll.setWidgetResizable(True);page_scroll.setWidget(page)
        self.tabs.insertTab(self.duo_page_index,page_scroll,'08 鼠标音区测试')
        self.duo_sync.setChecked(False);self.duo_sync.toggled.connect(lambda on:self.monitor_mode.setCurrentIndex(1 if on else 0))
        self.duo_sync.setToolTip('与连续监测互斥；每次击发抓取起音512点，缓冲忙时仍发声但不覆盖样本。')
    def monitor_cursor_readout(self,*args):
        texts=[]
        for i,lines in enumerate(self.monitor_cursors):
            if lines[0].isVisible():
                a,b=[x.value() for x in lines[:2]];d=abs(b-a);texts.append(f'{i+1}: t1={a:.3f},t2={b:.3f},Δt={d:.3f} ms'+(f', f={1000/d:.2f} Hz' if d else ''))
            if lines[2].isVisible():
                a,b=[x.value() for x in lines[2:]];texts.append(f'{i+1}: y1={a:.2f},y2={b:.2f},Δy={abs(b-a):.2f} PCM')
        self.monitor_readout.setText('；'.join(texts) or '右键开启游标；拖动游标不放大波形。')
    def enlarge_monitor(self,plot):
        self.monitor_zoomed=None if plot is self.monitor_zoomed else plot
        for p in self.monitor_all_plots:p.setVisible((self.monitor_zoomed is None or p is self.monitor_zoomed) and (p not in self.monitor_voice_plots or self.monitor_voice_plots.index(p)<len(self.monitor_plot_ids or [])))
    def reset_monitor_zoom(self):
        self.enlarge_monitor(None);self.follow_latest.setChecked(True)
        for p in self.monitor_all_plots:p.enableAutoRange()
    def select_monitor_voice(self,i,checked):
        ids=[n for n,b in enumerate(self.voice_tiles) if b.isChecked()]
        if len(ids)>4:
            self.voice_tiles[i].setChecked(False);self.monitor_selection_label.setText('最多选择4个声部；请先取消一条。');return
        self.monitor_selection=ids
        if self.engine.ready and self.engine.capabilities.get('duo_monitor'):
            j=self.submit_command('monitor.select',dict(voices=ids));self.monitor_job=j['id']
        self.monitor_selection_label.setText('已请求声部 '+str([n+1 for n in ids])+'，下一次完整采集生效。')
    def monitor_mode_changed(self,index):
        self.duo_sync.setChecked(index==1)
        if index==1:self.stop_live('已切换击发同步抓取')
    def toggle_monitor_live(self):
        self.monitor_mode.setCurrentIndex(0);self.toggle_live()
    def start_sine(self):
        self.stop_live('切换校准，等待在途抓取');self.duo_select_pending.clear();self.monitor_mode.setCurrentIndex(0)
        j=self.submit_command('sine.start',dict(frequency_hz=self.sine_frequency.value(),level_dbfs=self.sine_level.value(),channels=['left','right','both'][self.sine_channels.currentIndex()]))
        self.duo_last_job=j['id'];self.monitor_auto_job=j['id']
    def stop_sine(self):
        j=self.submit_command('sine.stop');self.duo_last_job=j['id'];self.monitor_auto_job=None
    def export_monitor(self):
        e=self.engine
        if e.audio is None or self.clear_pending:raise ValueError('没有完整采样可导出')
        path,_=W.QFileDialog.getSaveFileName(self,'导出五路输出及所选声部','监测采样.csv','CSV 文件 (*.csv)')
        if not path:return
        with e.lock:
            a=e.audio.copy();v=e.voice_audio.copy() if e.voice_audio is not None else np.empty((len(a),0));m=dict(e.audio_metadata);fs=e.fs
        with Path(path).open('w',encoding='utf-8-sig',newline='') as out:
            w=csv.writer(out);w.writerow(['段内时间_s',*e.channel_names,*[f'声部{i+1}_PCM' for i in m.get('monitor_voices',[])]])
            for i in range(len(a)):w.writerow([i/fs,*map(int,a[i]),*map(int,v[i])])
        Path(path).with_suffix('.json').write_text(json.dumps(dict(m,sample_rate=fs,source=e.source),ensure_ascii=False,indent=2),encoding='utf-8')
    def refresh_monitor(self):
        if not hasattr(self,'monitor_dock'):return
        e=self.engine;supported=e.capabilities.get('duo_monitor',False)
        for w in [self.sine_start_button,self.sine_stop_button,*self.voice_tiles]:w.setEnabled(supported and e.ready)
        if supported!=self.monitor_ui_supported:
            self.monitor_ui_supported=supported;self.monitor_dock.setVisible(supported)
        if e.capabilities.get('duo_mouse'):
            self.tabs.setTabText(1,'02 旧四声部（当前固件不可用）')
        else:self.tabs.setTabText(1,'02 声部与包络')
        if not supported:return
        if self.monitor_job and self.monitor_job in self.controller.jobs:
            j=self.controller.job(self.monitor_job)
            self.monitor_selection_label.setText('监测声部 '+str([n+1 for n in self.monitor_selection])+'：'+{'queued':'已排队','running':'已发送／等待应答','acknowledged':'设备已应答','completed':'设备接受，下次采集生效','failed':'失败：'+j.get('message',''),'cancelled':'已取消'}.get(j['state'],j['state']))
        if self.monitor_auto_job:
            j=self.controller.job(self.monitor_auto_job)
            if j['state'] in ('completed','failed','cancelled'):
                self.monitor_auto_job=None
                if j['state']=='completed' and not self.live_running and self.monitor_mode.currentIndex()==0:self.toggle_live()
        if self.live_running and self.duo_sync.isChecked():self.monitor_mode.setCurrentIndex(0)
        self.monitor_live_button.setText('停止监测' if self.live_running else '开始监测')
        self.monitor_note.setText(self.live_note.text()+(' · 独立正弦校准' if e.sine_state.get('mode') else ' · 演奏声部监测'))
        state=e.duo
        pending=self.monitor_job and self.monitor_job in self.controller.jobs and self.controller.job(self.monitor_job)['state'] not in ('completed','failed','cancelled')
        if not pending and self.monitor_selection!=e.monitor_ids:
            self.monitor_selection=list(e.monitor_ids)
            for i,b in enumerate(self.voice_tiles):b.setChecked(i in self.monitor_selection)
            self.monitor_selection_label.setText('板上已选声部 '+str([n+1 for n in e.monitor_ids])+'；当前片段 '+str([n+1 for n in e.audio_metadata.get('monitor_voices',[])]))
        for i,b in enumerate(self.voice_tiles):
            active=bool(state['active_mask']>>i&1);env=state['envelopes'][i]/65535
            text=f'{i+1}:'+str(state['notes'][i])+f'\n{env:.0%}' if active else f'{i+1}\n空闲'
            style=('background:#087c85;' if active else 'background:#213247;')+('border:1px solid #53dfc2;' if b.isChecked() else 'border:1px solid transparent;')
            if b.text()!=text:b.setText(text)
            if b.styleSheet()!=style:b.setStyleSheet(style)
        if self.pause.isChecked() or self.clear_pending:return
        if e.audio is None:
            for line in self.monitor_voice_lines:line.setData([],[])
            return
        key=(e.audio_session,e.audio_revision,self.live_view.currentIndex())
        if key==self.monitor_render_key:return
        with e.lock:history=list(e.audio_history);m=dict(e.audio_metadata);v=e.voice_audio.copy() if e.voice_audio is not None else None
        ids=m.get('monitor_voices',[])
        if ids!=self.monitor_plot_ids:self.monitor_plot_ids=list(ids);self.monitor_zoomed=None
        self.enlarge_monitor(self.monitor_zoomed) if self.monitor_zoomed is None else None
        for c,(plot,line) in enumerate(zip(self.monitor_voice_plots,self.monitor_voice_lines)):
            if c>=len(ids) or v is None:line.setData([],[]);continue
            plot.setTitle(f'声部{ids[c]+1} · '+('模拟PCM' if e.source.startswith('模拟') else '真实板内PCM'))
            if self.live_view.currentIndex()==0:x=np.arange(len(v))/e.fs*1000;y=v[:,c]
            else:
                xs=[];ys=[]
                for seg in history:
                    sv=seg.get('voice_samples');mi=seg.get('metadata',{}).get('monitor_voices',[])
                    if sv is None or ids[c] not in mi:continue
                    xs.extend([seg['relative']*1000-(len(sv)-1-np.arange(len(sv)))/seg['fs']*1000,[np.nan]])
                    ys.extend([sv[:,mi.index(ids[c])],[np.nan]])
                x=np.concatenate(xs) if xs else [];y=np.concatenate(ys) if ys else []
            line.setData(x,y,connect='finite')
            plot.setLabel('bottom','电脑接收相对时间（非板上测时）' if self.live_view.currentIndex() else '时间','ms')
            if self.follow_latest.isChecked() and len(x):plot.setXRange(float(x[0]),float(x[-2] if self.live_view.currentIndex() else x[-1]),padding=.02)
        if self.live_view.currentIndex():
            for c,line in enumerate(self.duo_scope_lines):
                xs=[];ys=[]
                for seg in history:
                    a=seg['samples'];xs.extend([seg['relative']*1000-(len(a)-1-np.arange(len(a)))/seg['fs']*1000,[np.nan]]);ys.extend([a[:,c+2],[np.nan]])
                if xs:line.setData(np.concatenate(xs),np.concatenate(ys),connect='finite')
        if not self.live_view.currentIndex():
            x=np.arange(len(e.audio))/e.fs*1000
            for c,line in enumerate(self.duo_scope_lines):line.setData(x,e.audio[:,c+2])
        f,db,_=spectrum(e.audio[:,4],e.fs);self.duo_fft_line.setData(f,db)
        if self.follow_latest.isChecked():
            self.duo_fft.setXRange(0,e.fs/2,padding=0)
            if self.live_view.currentIndex() and history:
                first,last=history[0],history[-1];lo=first['relative']*1000-(len(first['samples'])-1)/first['fs']*1000;hi=last['relative']*1000
            else:lo=0;hi=(len(e.audio)-1)/e.fs*1000
            self.duo_scope.setXRange(lo,max(lo+.001,hi),padding=.02)
        self.duo_scope.setTitle(f"{'校准正弦' if m.get('calibration') else '效果后左右'} · {len(e.audio)}点 / {e.fs}Hz · 采样{m.get('capture_id','—')} · {e.source}")
        self.duo_fft.setTitle(f'混音 FFT · 最近完整单段 · Δf={e.fs/len(e.audio):.3f}Hz')
        self.monitor_selection_label.setText('板上选路 '+str([n+1 for n in e.monitor_ids])+'；当前显示片段 '+str([n+1 for n in ids])+('（独立正弦，无演奏声部）' if m.get('calibration') else ''))
        self.monitor_render_key=key
    def check_external_focus(self):
        if self.engine.capabilities.get('instrument') and self.engine.instrument_state.get('mode',0)!=1 and not (self.engine.instrument_state.get('mode')==2 and self.engine.instrument_state.get('lesson_source')==1) and not self.engine.sine_state.get('enabled'):return
        active=W.QApplication.activeWindow()
        if active is None:
            if W.QApplication.applicationState()==C.Qt.ApplicationState.ApplicationActive:return
        p=active
        while p is not None:
            if p is self:return
            p=p.parentWidget()
        if self.engine.ready and (self.engine.duo_config.get('run') or self.engine.sine_state.get('enabled')):self.stop_duo()
