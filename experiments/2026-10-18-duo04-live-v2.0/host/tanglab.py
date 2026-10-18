import argparse,csv,json,sys,time
from pathlib import Path
import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore as C,QtGui as G,QtWidgets as W
from lab_engine import LabEngine
from lab_agent_gui import AgentGuiMixin
from lab_live import LiveMixin
from lab_duo_ui import DuoGuiMixin
import lab_protocol as P
from lab_ui import AnalysisMixin,ChineseViewBox,setup_plot,chinese_qt,REPORTS,CHANNELS
from app import PoseView,MainWindow as LegacyWindow
from protocol import from_euler,euler,relative

ROOT=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
COLORS=['#53dfc2','#79abff','#ffbd69','#e78cda','#eef5fa']
EDA_DEFAULT='D:/GOWINeda/Gowin/Gowin_V1.9.12.03_x64'

class Window(DuoGuiMixin,LiveMixin,AgentGuiMixin,AnalysisMixin,W.QMainWindow):
    def __init__(self):
        super().__init__();self.engine=LabEngine();self.origin=None;self.q=None;self.revision=-1;self.legacy=None
        self.setWindowTitle('TangLab · 138K 音频与 IMU 实验室');self.resize(1360,900)
        self.setStyleSheet('QWidget{background:#111c2c;color:#dfebf5;font-size:13px} QPushButton{background:#244b62;padding:8px;border:0;border-radius:4px} QPushButton:hover{background:#32657b} QLineEdit,QComboBox,QSpinBox,QDoubleSpinBox{background:#213247;padding:5px} QTabBar::tab{padding:12px} QTabBar::tab:selected{background:#245b63} QHeaderView::section{background:#213247;padding:5px} QPlainTextEdit{background:#142337}')
        central=W.QWidget();self.setCentralWidget(central);layout=W.QVBoxLayout(central)
        row=W.QHBoxLayout();title=W.QLabel('TangLab  /  FPGA 音频与姿态调试');title.setStyleSheet('font-size:24px;color:#53dfc2;font-weight:bold');row.addWidget(title);row.addStretch()
        self.button(row,'模拟演示',self.demo);self.button(row,'使用说明',lambda:self.open_file(ROOT/'使用说明.txt'));layout.addLayout(row)
        self.banner=W.QLabel('连接板卡或运行模拟演示');layout.addWidget(self.banner)
        row=W.QHBoxLayout();self.port=W.QComboBox();row.addWidget(self.port,1);self.button(row,'刷新串口',self.ports)
        row.addWidget(W.QLabel('波特率'));self.baud=W.QComboBox();self.baud.setObjectName('baudrate');self.baud.addItems(['115200','230400','460800','921600','1000000','1500000','2000000','3000000']);self.baud.setCurrentText('921600');self.baud.setToolTip('必须与 FPGA 固件一致；更改后断开并重新连接生效。');row.addWidget(self.baud);self.button(row,'连接 FPGA',self.connect);self.button(row,'断开',lambda:self.submit_command('disconnect'));self.button(row,'通信往返测量',lambda:self.submit_command('ping'));layout.addLayout(row)
        self.tabs=W.QTabWidget();layout.addWidget(self.tabs)
        self.audio_page();self.control_page();self.imu_page();self.stats_page();self.eda_page();self.spectrum_page();self.agent_page(ROOT);self.duo_page()
        self.add_tips()
        self.timer=C.QTimer(self);self.timer.timeout.connect(self.refresh);self.timer.start(100);self.ports()
    def button(self,row,text,fn):
        b=W.QPushButton(text);b.clicked.connect(lambda:self.safe(fn));row.addWidget(b);return b
    def safe(self,fn):
        try:fn()
        except Exception as e:W.QMessageBox.warning(self,'操作未完成',str(e))
    def page(self,title):
        p=W.QWidget();l=W.QVBoxLayout(p);self.tabs.addTab(p,title);return l
    def open_file(self,path):G.QDesktopServices.openUrl(C.QUrl.fromLocalFile(str(Path(path).resolve())))
    def ports(self):
        from serial.tools.list_ports import comports
        self.port.clear()
        for p in comports():self.port.addItem(f'{p.device} · {p.description}',p.device)
    def connect(self):
        if not self.port.currentData():raise ValueError('未发现串口：连接板上 USB JTAG/UART 接口，检查驱动')
        self.submit_command('connect',dict(port=self.port.currentData(),baud=int(self.baud.currentText())));self.revision=-1;self.origin=None
    def demo(self):self.submit_command('demo');self.revision=-1;self.tabs.setCurrentIndex(0)
    def audio_page(self):
        l=self.page('01  音频示波器');r=W.QHBoxLayout()
        self.button(r,'抓取 2048 点',lambda:self.submit_command('capture',dict(trigger=self.trigger.currentIndex())))
        self.trigger=W.QComboBox();self.trigger.addItems(['立即触发','混音上升过零']);r.addWidget(self.trigger)
        self.button(r,'开启包络预览',self.preview)
        self.pause=W.QCheckBox('暂停绘图');r.addWidget(self.pause)
        self.stacked=W.QCheckBox('分栏显示');self.stacked.setChecked(True);self.stacked.toggled.connect(self.layout_plots);r.addWidget(self.stacked)
        self.button(r,'导出采样 CSV',self.export_audio);l.addLayout(r)
        self.live_controls(l)
        r=W.QHBoxLayout();self.button(r,'清空波形',self.clear_waveforms);self.button(r,'恢复全部波形',lambda:self.focus_wave(None));self.button(r,'重置波形缩放',self.reset_wave_zoom)
        r.addWidget(W.QLabel('单击波形放大，再次单击恢复；滚轮独立缩放，拖动平移。'));l.addLayout(r)
        self.init_cursors(l)
        self.audio_note=W.QLabel('等待完整采样 · 包络预览不用于 FFT');l.addWidget(self.audio_note)
        self.graphics=pg.GraphicsLayoutWidget();self.graphics.setBackground('#111c2c');l.addWidget(self.graphics,3)
        self.plots=[];self.curves=[];self.layout_plots()
        self.fft=pg.PlotWidget(title='混音 FFT · 完整采样 / 汉宁窗',viewBox=ChineseViewBox());self.fft.setBackground('#111c2c');setup_plot(self.fft);self.fft.setLabel('bottom','频率','Hz');self.fft.setLabel('left','幅度','dBFS');self.fftline=self.fft.plot(pen='#53dfc2');l.addWidget(self.fft,1)
        self.metrics=W.QLabel('峰值 —   RMS —   削波 —');l.addWidget(self.metrics)
        self.cursors=W.QLabel();self.cursors.setWordWrap(True);l.addWidget(self.cursors);self.update_cursor_readout()
    def preview(self):
        self.stop_live('已切换到包络预览')
        self.submit_command('preview',dict(enabled=True));self.fftline.setData([],[])
    def clear_waveforms(self):
        self.stop_live('波形已清空')
        # Stop a running preview first so that the cleared plots stay empty.
        if self.engine.ready and not self.engine.source.startswith('模拟'):
            self.submit_command('preview',dict(enabled=False))
        with self.controller.lock:
            self.clear_pending=any(j['state'] in ('queued','running','acknowledged','simulated') for j in self.controller.jobs.values())
        if not self.clear_pending:self.engine.clear_waveforms()
        self.revision=self.engine.audio_revision
        for line in self.curves:line.setData([],[])
        self.fftline.setData([],[])
        self.spectrum_key=None;self.spectrum_data=None
        if hasattr(self,'spectrum_curves'):
            for line in self.spectrum_curves:line.setData([],[])
            self.spectrum_note.setText('波形已清空；请重新抓取完整样本后进行幅相分析。')
        self.metrics.setText('峰值 —   RMS —   削波 —')
        self.audio_note.setText('波形已清空 · 包络预览已停止')
    def layout_plots(self):
        if getattr(self,'focused',None) is not None:self.focus_wave(None)
        self.focused=None
        self.graphics.clear();self.plots=[];self.curves=[]
        for i in range(5):
            if self.stacked.isChecked() or i==0:
                vb=ChineseViewBox();vb.selected.connect(lambda index=i:self.focus_wave(None if self.focused==index else index))
                vb.sigRangeChangedManually.connect(lambda *_:self.follow_latest.setChecked(False))
                p=self.graphics.addPlot(row=i if self.stacked.isChecked() else 0,col=0,viewBox=vb);p.showGrid(x=True,y=True,alpha=.15);p.addLegend(offset=(8,0));setup_plot(p);p.setLabel('left','幅值',units='PCM');p.getAxis('left').enableAutoSIPrefix(False);p.setLabel('bottom','时间','ms');self.plots.append(p)
            self.curves.append(p.plot(pen=pg.mkPen(COLORS[i],width=1.2),name=CHANNELS[i]))
        self.mount_cursors();self.revision=-1
    def focus_wave(self,index):
        if not self.stacked.isChecked():return
        for p in self.plots:
            if p in self.graphics.ci.items:self.graphics.ci.removeItem(p)
        self.focused=index
        if index is not None:self.cursor_channel.setCurrentIndex(index)
        for i,p in enumerate(self.plots):
            if index is None or i==index:self.graphics.ci.addItem(p,row=i if index is None else 0,col=0)
    def reset_wave_zoom(self):
        for i,p in enumerate(self.plots):
            if self.focused is None or i==self.focused:p.enableAutoRange()
    def add_tips(self):
        tips={
            '模拟演示':'不连接硬件，查看模拟波形和姿态；这些数据不是实测结果。',
            '使用说明':'打开接线、下载工程和基本操作说明。',
            '刷新串口':'重新查找串口。插入板卡调试 USB 后点击此按钮。',
            '连接 FPGA':'用所选波特率连接串口并握手，更改后需重新连接；需先下载配套 FPGA 工程。',
            '断开':'断开串口并停止当前记录。',
            '通信往返测量':'发送一次探测命令，在延迟页查看 PC→FPGA→PC 往返时间。',
            '抓取 2048 点':'同步采集四声部和混音，每通道 2048 点，用于精确波形和 FFT 分析。',
            '开启包络预览':'连续显示最小/最大值包络，节省串口带宽；包络不能用于 FFT。',
            '清空波形':'清除当前完整采样、包络预览和频谱，并停止包络预览；不改变 FPGA 声部参数或串口连接。',
            '导出采样 CSV':'保存最近一次完整抓取的时间及五通道样本。请先抓取。',
            '恢复全部波形':'退出单路放大，恢复五条波形；保留各路缩放范围。',
            '重置波形缩放':'让当前放大的波形自动适应数据；全部显示时重置所有波形。',
            '应用四个声部':'把表格参数发送到 FPGA；仅修改表格不会立即改变硬件。',
            '全部松键 / 释音':'关闭四路按键，按各自 释音时间逐渐释音。',
            '设置接口并复位 IMU':'应用接口模式并复位传感器。先断电按说明改 PS0/PS1 接线，再上电操作。',
            '归中':'将当前姿态作为显示零位，不改变传感器内部校准。',
            '应用报告配置':'向 SHTP/SPI 模式请求姿态、加速度和角速度报告；RVC 不支持此配置。',
            '旧版直连工具':'打开原有 IMU 串口工具；当前 FPGA 转发测试使用主窗口。',
            '开始记录':'将接收报文保存到程序目录 agent-results 下唯一会话文件夹的 recording 子目录。',
            '停止记录':'结束记录并保存统计结果。',
            '打开回放':'选择包含 metadata.json 和 raw.jsonl 的记录文件夹。',
            '导出统计 JSON':'保存延迟、丢包、接口模式和测试参数，便于比较结果。',
            '选择工程':'选择 Gowin 的 .gprj 或 .gpr 工程文件。',
            '综合':'检查 HDL 并生成综合结果；不会下载到板卡。',
            '综合＋布局布线':'生成可下载文件并输出资源和时序报告，可能需要数分钟。',
            '停止本次编译':'停止本次启动的 gw_sh 编译进程。',
            '打开工程编辑器':'用所选 Gowin 安装目录中的 IDE 打开当前工程。',
            '打开下载工具':'打开官方烧录工具。请手动选择器件和 .fs 文件下载。',
            '复位本路游标':'把所选声部的四条游标移到当前视窗内，不改变开关状态。',
            '导出幅相谱 CSV':'导出所选声部的频率、幅度和相位；被屏蔽的相位留空。',
            '开启本机接口':'仅在 127.0.0.1 开启带令牌的 API，允许本机 agent 调用。',
            '关闭本机接口':'停止 API、删除会话令牌文件，并请求取消正在进行的命令。',
            '复制连接信息':'复制实际地址和会话令牌，仅供本机使用，请勿分享。',
            '取消当前命令':'取消当前等待或测试；自动测试会尝试停止记录、关闭预览并松键。',
            '打开测试结果目录':'打开 agent-results，内含自动报告、采样和原始报文记录。',
            '打开输出目录':'打开当前工程旁的 impl 文件夹；布局布线结果通常位于 pnr。'}
        for b in self.findChildren(W.QPushButton):
            if b.text() in tips:b.setToolTip(tips[b.text()])
        for w,text in [(self.port,'选择板卡 USB JTAG/UART 对应的 COM；com0com 是虚拟串口。'),
                       (self.eda,'选择 Gowin 安装根目录，其下应有 IDE 和 Programmer 文件夹，不是 exe 文件。'),
                       (self.project,'完整工程文件路径。默认是随包 fpga/tanglab.gprj，适用于普通 Dock 的 138K C 版本。'),
                       (self.trigger,'立即触发直接抓取；上升过零等待混音从负变正，静音时可能持续等待。'),
                       (self.pause,'仅暂停屏幕刷新，不停止串口接收或记录。'),
                       (self.stacked,'勾选：五条波形分别显示、独立缩放，单击可放大。取消：五路叠加，共用坐标。'),
                       (self.mode,'须与传感器 PS1/PS0 的实际接线一致；切换模式前先断电改线。'),
                       (self.hz,'请求的报告频率，实际输出受传感器支持及总线负载影响。')]:w.setToolTip(text)
        names={'hz':'音调频率，单位 Hz。','gain':'声部音量，0 为静音；多路音量过高会造成混音削波。','wave':'选择 FPGA 生成的基本波形。','gate':'勾选按键发声，取消按释音时间松键；修改后点击应用。','attack':'从静音升到峰值的时间，单位毫秒。','decay':'从峰值降到持续电平的时间，单位毫秒。','sustain':'按键保持期间的电平比例，范围 0～1。','release':'松键后降到静音的时间，单位毫秒。'}
        for cells in self.controls:
            for key,w in cells:w.setToolTip(names[key])
    def control_page(self):
        self.voice_edit_revision=0;self.voice_edit_time=0.;self.voice_job_revisions={};self.latest_voice_job=None
        l=self.page('02  声部与包络');l.addWidget(W.QLabel('默认静音。钢琴保持/衰减需要 TangLab 1.3 固件；保留16位增益和DAC约30dB衰减。抓取为衰减前数据。'))
        self.table=W.QTableWidget(4,9);self.table.setHorizontalHeaderLabels(['声部','频率 Hz','增益','波形','按下/发声','起音 ms','衰减 ms','持续电平','释音 ms']);self.controls=[]
        for i,v in enumerate(self.engine.voices):
            self.table.setItem(i,0,W.QTableWidgetItem(CHANNELS[i]));cells=[]
            for key,low,high in [('hz',1,20000),('gain',0,1),('wave',0,4),('gate',0,1),('attack',0,5000),('decay',0,5000),('sustain',0,1),('release',0,5000)]:
                if key=='wave':w=W.QComboBox();w.addItems(['正弦','锯齿','方波','三角','钢琴（合成）'])
                elif key=='gate':w=W.QCheckBox();w.setChecked(v[key])
                else:w=W.QDoubleSpinBox();w.setRange(low,high);w.setDecimals(3 if high==1 else 1);w.setValue(v[key])
                if key=='gain':w.setDecimals(5);w.setSingleStep(.0001)
                if key=='hz':w.setDecimals(2)
                cells.append((key,w));self.table.setCellWidget(i,len(cells),w)
            self.controls.append(cells)
        self.table.horizontalHeader().setSectionResizeMode(W.QHeaderView.ResizeMode.Stretch);self.table.setMinimumHeight(240);l.addWidget(self.table)
        r=W.QHBoxLayout();self.button(r,'应用四个声部',self.apply_voices);self.button(r,'全部松键 / 释音',self.release);l.addLayout(r)
        r=W.QHBoxLayout();r.addWidget(W.QLabel('钢琴设置声部'))
        self.piano_channel=W.QComboBox();self.piano_channel.addItems(CHANNELS[:4]);r.addWidget(self.piano_channel)
        self.piano_hold=W.QCheckBox('保持声音');r.addWidget(self.piano_hold)
        r.addWidget(W.QLabel('自然衰减至10%（秒）'));self.piano_decay=W.QDoubleSpinBox();self.piano_decay.setRange(.2,30);self.piano_decay.setDecimals(1);self.piano_decay.setSingleStep(.2);self.piano_decay.setValue(6);r.addWidget(self.piano_decay)
        self.piano_values=[dict(v) for v in self.engine.piano_settings];self.piano_edit_channel=0
        for cells in self.controls:
            for key,w in cells:
                signal=w.currentIndexChanged if key=='wave' else w.toggled if key=='gate' else w.valueChanged
                signal.connect(self.voice_draft_changed)
        self.piano_channel.currentIndexChanged.connect(self.change_piano_channel)
        self.piano_hold.toggled.connect(self.save_piano_controls);self.piano_decay.valueChanged.connect(self.save_piano_controls)
        self.piano_hold.setToolTip('保持实际声音，不是暂停绘图。需1.3固件；增益、ADSR持续电平应大于0；松键仍可收音。')
        self.piano_decay.setToolTip('仅钢琴主体的自然衰减；从当前能量衰减到10%的时间。关闭保持后生效，ADSR另作用于总体。')
        l.addLayout(r);self.piano_hint=W.QLabel('保持/衰减调整需要TangLab 1.3；仍点击“应用四个声部”提交。');l.addWidget(self.piano_hint)
        self.voice_apply_status=W.QLabel('修改参数后点击“应用四个声部”。');l.addWidget(self.voice_apply_status)
        l.addWidget(W.QLabel('钢琴在波形下拉框中选择，仍点击“应用四个声部”。重新起音：取消发声并应用，再勾选发声并应用。'))
        l.addWidget(W.QLabel('默认测试频率 375 / 750 / 1125 / 1500 Hz，可逐路取消发声并查看频谱。\n起音/衰减/持续/释音（ADSR）按采样步进量量化；增益过高会使混音饱和。'));l.addStretch()
    def apply_voices(self):
        self.submit_command('voices.set',dict(voices=self.voice_settings()))
    def voice_settings(self):
        self.save_piano_controls()
        voices=[]
        for i,cells in enumerate(self.controls):
            settings={k:(w.currentIndex() if k=='wave' else w.isChecked() if k=='gate' else w.value()) for k,w in cells};voices.append(dict(channel=i,**settings))
            if self.engine.capabilities.get('piano_control'):voices[-1].update(self.piano_values[i])
        return voices
    def save_piano_controls(self,*args):
        settings=dict(piano_hold=self.piano_hold.isChecked(),piano_decay_s=self.piano_decay.value())
        if settings!=self.piano_values[self.piano_edit_channel]:
            self.piano_values[self.piano_edit_channel]=settings;self.voice_draft_changed()
    def voice_draft_changed(self,*args):
        self.voice_edit_revision+=1;self.voice_edit_time=time.time()
        if hasattr(self,'voice_apply_status'):self.voice_apply_status.setText('当前修改尚未应用。')
    def change_piano_channel(self,index):
        self.save_piano_controls();self.piano_edit_channel=index;self.show_piano_controls()
    def show_piano_controls(self):
        settings=self.piano_values[self.piano_edit_channel]
        with C.QSignalBlocker(self.piano_hold),C.QSignalBlocker(self.piano_decay):
            self.piano_hold.setChecked(settings['piano_hold']);self.piano_decay.setValue(settings['piano_decay_s'])
    def sync_audio_capabilities(self):
        supported=self.engine.capabilities.get('piano_control',False)
        self.piano_hold.setEnabled(supported);self.piano_decay.setEnabled(supported)
        warning=any(p['piano_hold'] and dict(cells)['wave'].currentIndex()==4 and (dict(cells)['gain'].value()==0 or dict(cells)['sustain'].value()==0) for p,cells in zip(self.piano_values,self.controls))
        self.piano_hint.setText('保持仍受ADSR影响：增益和持续电平需大于0。' if warning else ('钢琴保持/衰减通过“应用四个声部”提交；松键仍可收音。' if supported else '保持/衰减调整需要TangLab 1.3；当前固件不支持。'))
    def release(self):
        for cells in self.controls:dict(cells)['gate'].setChecked(False)
        self.apply_voices()
    def imu_page(self):
        l=self.page('03  IMU 三接口');r=W.QHBoxLayout();self.mode=W.QComboBox();self.mode.addItems(['UART-RVC · 115200','UART-SHTP · 3 Mbps','SPI Mode 3 · 1 MHz']);r.addWidget(self.mode)
        self.button(r,'设置接口并复位 IMU',lambda:self.submit_command('imu.mode',dict(mode=self.mode.currentIndex())));self.button(r,'归中',self.recenter);l.addLayout(r)
        self.wiring=W.QLabel();self.wiring.setWordWrap(True);l.addWidget(self.wiring)
        r=W.QHBoxLayout();self.hz=W.QSpinBox();self.hz.setRange(10,400);self.hz.setValue(100);r.addWidget(W.QLabel('姿态 / 加速度 / 角速度请求 Hz'));r.addWidget(self.hz)
        self.button(r,'应用报告配置',lambda:self.submit_command('imu.configure',dict(reports={5:self.hz.value(),1:self.hz.value(),2:self.hz.value()})));self.button(r,'旧版直连工具',self.show_legacy);l.addLayout(r)
        splitter=W.QSplitter();self.pose=PoseView();splitter.addWidget(self.pose);self.imu_text=W.QPlainTextEdit();self.imu_text.setReadOnly(True);splitter.addWidget(self.imu_text);l.addWidget(splitter,2)
        self.raw=W.QPlainTextEdit();self.raw.setReadOnly(True);self.raw.setMaximumHeight(140);l.addWidget(self.raw)
    def recenter(self):
        if self.q is None:raise ValueError('等待有效姿态')
        self.origin=self.q
    def show_legacy(self):
        if self.legacy is None:self.legacy=LegacyWindow()
        self.legacy.show()
    def stats_page(self):
        l=self.page('04  延迟与记录');r=W.QHBoxLayout();self.button(r,'开始记录',self.record);self.button(r,'停止记录',lambda:self.submit_command('record.stop'));self.button(r,'打开回放',self.replay);self.button(r,'导出统计 JSON',self.export_stats);l.addLayout(r)
        self.stats=W.QPlainTextEdit();self.stats.setReadOnly(True);l.addWidget(self.stats)
        l.addWidget(W.QLabel('总线耗时：SPI/UART-SHTP 使用中断或事务起点，RVC 使用首字节起始位。\nPC 往返包括 USB、驱动和系统调度；这些均不代表动作到模拟音频的完整延迟。'))
    def record(self):self.submit_command('record.start')
    def replay(self):
        p=W.QFileDialog.getExistingDirectory(self,'选择 TangLab 记录目录',str(ROOT/'recordings'))
        if p:self.submit_command('replay',dict(path=p));self.revision=-1
    def export_stats(self):
        p,_=W.QFileDialog.getSaveFileName(self,'保存统计',str(ROOT/'延迟统计.json'),'JSON 文件 (*.json)')
        if p:Path(p).write_text(json.dumps(self.engine.stats(),ensure_ascii=False,indent=2),encoding='utf-8')
    def write_audio(self,p):
        if self.clear_pending:raise ValueError('波形已清空，正在等待在途采集结束')
        if self.engine.audio is None:raise ValueError('先抓取完整采样')
        with Path(p).open('w',newline='',encoding='utf-8-sig') as f:
            w=csv.writer(f);ids=self.engine.audio_metadata.get('monitor_voices',[]);v=self.engine.voice_audio
            w.writerow(['time_s',*self.engine.channel_names,*[f'声部{n+1}_PCM' for n in ids]])
            for i,row in enumerate(self.engine.audio):w.writerow([i/self.engine.fs,*map(int,row),*(map(int,v[i]) if v is not None else [])])
        if self.engine.capabilities.get('duo_mouse'):
            Path(str(p)+'.json').write_text(json.dumps(dict(self.engine.audio_metadata,channels=self.engine.channel_names,source=self.engine.source,sample_rate=self.engine.fs),ensure_ascii=False,indent=2),encoding='utf-8')
    def export_audio(self):
        p,_=W.QFileDialog.getSaveFileName(self,'保存完整采样',str(ROOT/'音频采样.csv'),'CSV 文件 (*.csv)')
        if p:self.write_audio(p)
    def eda_page(self):
        l=self.page('05  Gowin 工程');f=W.QFormLayout();self.eda=W.QLineEdit(EDA_DEFAULT);self.project=W.QLineEdit(str(ROOT/'fpga/tanglab.gprj'));f.addRow('Gowin 安装目录',self.eda);f.addRow('工程 .gprj',self.project);l.addLayout(f)
        r=W.QHBoxLayout();self.button(r,'选择工程',self.choose_project);self.button(r,'综合',lambda:self.submit_command('eda.synthesis'));self.button(r,'综合＋布局布线',lambda:self.submit_command('eda.build'));self.button(r,'停止本次编译',lambda:self.submit_command('eda.stop'));l.addLayout(r)
        r=W.QHBoxLayout();self.button(r,'打开工程编辑器',lambda:self.launch('IDE/bin/gw_ide.exe',[self.project.text()]));self.button(r,'打开下载工具',lambda:self.launch('Programmer/bin/programmer.exe',[]));self.button(r,'打开输出目录',lambda:self.open_file(Path(self.project.text()).parent/'impl'));l.addLayout(r)
        self.log=W.QPlainTextEdit();self.log.setReadOnly(True);l.addWidget(self.log)
        self.process=C.QProcess(self);self.process.setProcessChannelMode(C.QProcess.ProcessChannelMode.MergedChannels);self.process.readyReadStandardOutput.connect(self.read_log)
        self.process.finished.connect(lambda code,status:self.log.appendPlainText(f'进程结束：退出码 {code}。检查 ERROR、时序报告及本次输出文件。'))
        self.process.errorOccurred.connect(lambda e:self.log.appendPlainText('启动/运行失败：'+self.process.errorString()))
    def choose_project(self):
        p,_=W.QFileDialog.getOpenFileName(self,'选择 Gowin 工程',self.project.text(),'Gowin (*.gprj *.gpr)')
        if p:self.project.setText(p)
    def launch(self,relative,args):
        exe=Path(self.eda.text())/relative
        if not exe.is_file():raise ValueError('工具不存在：'+str(exe))
        ok,pid=C.QProcess.startDetached(str(exe),args)
        if not ok:raise ValueError('工具启动失败')
    def build(self,pnr):
        if self.process.state()!=C.QProcess.ProcessState.NotRunning:raise ValueError('已有编译正在运行')
        project=Path(self.project.text()).resolve();exe=Path(self.eda.text())/'IDE/bin/gw_sh.exe'
        if not project.is_file() or not exe.is_file():raise ValueError('工程或 gw_sh 不存在')
        path=project.as_posix()
        if any(c in path for c in '{}\n\r'):raise ValueError('工程路径不能包含花括号或换行')
        options='set_option -top_module top\nset_option -use_cpu_as_gpio 1\nset_option -use_sspi_as_gpio 1\n' if project.name=='tanglab.gprj' else ''
        if project.name=='tanglab_duo02_mouse.gprj':options='set_option -top_module top_duo02_mouse\nset_option -route_option 1\nset_option -timing_driven 1\n'
        script=project.parent/'tanglab_build.tcl';script.write_text(f'open_project {{{path}}}\n{options}run {"all" if pnr else "syn"}\n',encoding='utf-8')
        self.log.clear();self.log.appendPlainText('开始编译：'+str(project));self.process.setWorkingDirectory(str(project.parent));self.process.start(str(exe),[str(script)])
    def stop_build(self):
        if self.process.state()!=C.QProcess.ProcessState.NotRunning:self.process.kill();self.log.appendPlainText('已停止本次 gw_sh 进程')
    def read_log(self):self.log.appendPlainText(bytes(self.process.readAllStandardOutput()).decode('utf-8',errors='replace'))
    def refresh(self):
        self.sync_audio_capabilities()
        self.service_live()
        e=self.engine;self.banner.setText(f'{e.source}  |  {e.device}  |  {e.status}')
        if not self.clear_pending and not self.pause.isChecked() and e.audio is not None and self.revision!=e.audio_revision:
            draw_started=time.monotonic()
            with e.lock:a=e.audio.copy();fs=e.fs;draw_revision=e.audio_revision
            self.draw_live(a,fs)
            v=a[:,4].astype(float)/32768;window=np.hanning(len(v));spec=np.abs(np.fft.rfft(v*window))*2/max(1,window.sum())
            self.fftline.setData(np.fft.rfftfreq(len(v),1/fs),20*np.log10(np.maximum(spec,1e-8)));self.fft.setXRange(0,5000)
            self.metrics.setText(f'混音峰值 {np.max(np.abs(v)):.4f} FS   RMS {np.sqrt(np.mean(v*v)):.4f} FS   板上削波 {e.clips}')
            self.audio_note.setText(f'{e.source} · 完整采样 {len(a)} 点 / 通道，{fs} Hz；FFT 基于此抓取'+(' · 当前采样为静音' if not np.any(a) else ''));self.revision=draw_revision
            e.note_audio_drawn(draw_revision,draw_started)
        elif not self.clear_pending and not self.pause.isChecked() and e.envelope and e.audio is None:
            points=list(e.envelope);x=np.arange(len(points))*10
            for i,line in enumerate(self.curves):line.setData(np.repeat(x,2),np.array([v[1][i] for v in points]).ravel())
            self.audio_note.setText('实时最小/最大值包络预览 · 点击抓取查看完整波形与 FFT')
        self.update_cursor_readout()
        if not self.clear_pending and not self.pause.isChecked():self.update_spectrum()
        s=e.stats()
        lines=[f"数据来源：{s['source']}",f"接口模式：{['UART-RVC','UART-SHTP','SPI'][s['mode']]}",
               f"接收速率：{s['rx_bytes_per_s']:.0f} 字节/秒",f"收到报文：{s['frames']}    缺失报文：{s['missing_frames']}",
               f"通信丢包率：{s['loss_rate']:.2%}    校验/解析错误：{s['crc_errors']}",
               f"板上丢弃：{s['board_drops']}    音频削波：{s['clipping']}",
               f"音频采样率：{s['sample_rate']} Hz    FPGA 时钟：{s['clock_hz']/1e6:g} MHz",'']
        for key,label in [('bus_ms','总线传输耗时'),('fpga_packet_ms','FPGA 报文处理耗时'),('pc_roundtrip_ms','电脑通信往返耗时')]:
            v=s[key];lines.append(label)
            if not v['n']:lines.append('  暂无测量数据（模拟演示不生成实测延迟）')
            else:lines.extend([f"  有效样本：{v['n']}",f"  最小：{v['min']:.3f} ms    中位数：{v['median']:.3f} ms",f"  P95（95% 样本不超过）：{v['p95']:.3f} ms    最大：{v['max']:.3f} ms"])
            lines.append('')
        lines.extend([f"记录状态：{'正在记录' if e.recorder else '未在记录'}",f"记录丢弃：{s['record_drops']}",f"记录错误：{s['record_error'] or '无'}",'',s['note']])
        self.stats.setPlainText('\n'.join(lines))
        self.wiring.setText(['RVC：PS1=0、PS0=1；固定 100 Hz，仅姿态角和加速度。','SHTP：PS1=1、PS0=0；先复位等待启动，再应用报告配置。','SPI：PS1=1；PS0 接 FPGA WAKE，启动期间为高。CS/INT/RST 都需要连接。'][self.mode.currentIndex()]+'  断电后按 TXT 改线。')
        snap=e.imu.snapshot();lines=[];candidates=[]
        for kind,(ns,s) in snap['latest'].items():
            lines.append(f'{REPORTS.get(kind,kind)}: '+', '.join(f'{v:+.4f}' for v in s.values)+f'  [{(time.perf_counter_ns()-ns)/1e6:.0f} ms 前]')
            if kind in ('rvc','rotation','game','stabilized'):candidates.append((ns,from_euler(*s.values[:3]) if kind=='rvc' else s.values))
        if candidates:
            self.q=max(candidates,key=lambda v:v[0])[1];self.pose.q=relative(self.q,self.origin) if self.origin else self.q;self.pose.valid=True;self.pose.update()
            lines.insert(0,'偏航 / 俯仰 / 横滚：'+' / '.join(f'{x:.2f}°' for x in euler(self.pose.q)))
        else:self.q=None;self.pose.valid=False;self.pose.update()
        lines+=['','报告计数：'+'，'.join(f'{REPORTS.get(k,k)} {v}' for k,v in snap['counts'].items()),'配置应答（报告编号：间隔 μs）：'+('，'.join(f'{k}：{v}' for k,v in snap['confirmed'].items()) or '无'),'配置失败：'+('，'.join(f'{k}：{v}' for k,v in snap['failures'].items()) or '无')]
        self.imu_text.setPlainText('\n'.join(lines));self.raw.setPlainText('\n'.join(e.raw)[-6000:])
    def closeEvent(self,event):
        self.duo_timer.stop();self.stop_duo();self.agent_timer.stop();self.agent.stop();self.controller.shutdown();self.timer.stop();self.stop_build();self.process.waitForFinished(2000);self.engine.close();self.engine.imu.disconnect()
        if self.legacy:self.legacy.close()
        event.accept()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--demo',action='store_true');parser.add_argument('--smoke',type=str);parser.add_argument('--agent-smoke',type=str);parser.add_argument('--live-smoke',type=str);parser.add_argument('--piano-smoke',type=str);parser.add_argument('--voice-draft-smoke',type=str);parser.add_argument('--duo-smoke',type=str);parser.add_argument('--instrument-smoke',type=str);args=parser.parse_args()
    app=W.QApplication(sys.argv);chinese_qt(app)
    fid=G.QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc')
    families=G.QFontDatabase.applicationFontFamilies(fid)
    app.setFont(G.QFont(families[0] if families else 'Microsoft YaHei UI',10));window=Window();window.show()
    if args.demo or args.smoke or args.live_smoke:window.demo()
    if args.instrument_smoke:
        from lab_duo_smoke import start
        start(window,app,args.instrument_smoke,instrument=True)
    if args.duo_smoke:
        from lab_duo_smoke import start
        start(window,app,args.duo_smoke)
    if args.voice_draft_smoke:
        out=Path(args.voice_draft_smoke);out.mkdir(parents=True,exist_ok=True)
        window.agent_timer.stop();window.engine.demo()
        cells=dict(window.controls[0]);cells['wave'].setCurrentIndex(4);cells['gain'].setValue(.002);cells['gate'].setChecked(False)
        window.apply_voices();stage=[0];deadline=time.monotonic()+12
        def draft_check():
            try:
                job=window.controller.job(window.last_agent_job)
                if time.monotonic()>deadline:raise TimeoutError('打包程序检查超时')
                if job['state'] not in ('completed','failed'):return
                assert job['state']=='completed',job
                if stage[0]==0:
                    cells['gate'].setChecked(True);window.refresh_agent()
                    assert cells['gate'].isChecked(),'旧命令覆盖新发声勾选'
                    window.piano_hold.setChecked(True);window.apply_voices();stage[0]=1;return
                if stage[0]==1:
                    window.refresh_agent();assert window.engine.voices[0]['gate']
                    window.tabs.setCurrentIndex(1);app.processEvents();window.grab().save(str(out/'声部状态.png'))
                    window.toggle_live();stage[0]=2;stage.append(window.engine.audio_count+3);return
                if window.engine.audio_count<stage[1]:return
                window.stop_live();window.write_audio(out/'最近一段.csv');window.write_history(out/'滚动历史.csv')
                window.tabs.setCurrentIndex(0);window.refresh();app.processEvents();window.grab().save(str(out/'连续采集.png'))
                (out/'result.json').write_text(json.dumps(dict(result='PASS',source='模拟',draft_preserved=True,gate=window.engine.voices[0]['gate'],segments=window.engine.audio_count,shape=list(window.engine.audio.shape)),ensure_ascii=False),encoding='utf-8')
                window.draft_timer.stop();window.close()
            except Exception as exc:
                (out/'result.json').write_text(json.dumps(dict(result='FAIL',error=str(exc)),ensure_ascii=False),encoding='utf-8');window.draft_timer.stop();window.close();app.exit(1)
        window.draft_timer=C.QTimer(window);window.draft_timer.timeout.connect(draft_check);window.draft_timer.start(10)
    if args.piano_smoke:
        out=Path(args.piano_smoke);out.mkdir(parents=True,exist_ok=True)
        window.engine.demo()
        for i,cells in enumerate(window.controls):
            values=dict(hz=(261.63,329.63,392.,523.25)[i],gain=.002,wave=4,gate=i==0,attack=3,decay=80,sustain=.7,release=100)
            for key,w in cells:
                if key=='wave':w.setCurrentIndex(values[key])
                elif key=='gate':w.setChecked(values[key])
                else:w.setValue(values[key])
        window.piano_hold.setChecked(True);window.piano_decay.setValue(6)
        window.apply_voices()
        def finish_piano():
            try:
                job=window.controller.job(window.last_agent_job)
                assert job['state']=='completed',job
                assert window.engine.voices[0]['wave']==4 and window.engine.voices[0]['gate']
                assert window.engine.piano_settings[0]['piano_hold']
                assert all(not v['gate'] for v in window.engine.voices[1:])
                assert dict(window.controls[0])['wave'].currentIndex()==4
                assert np.any(window.engine.audio[:,0]) and not np.any(window.engine.audio[:,1:4])
                window.refresh();window.tabs.setCurrentIndex(1);app.processEvents();window.grab().save(str(out/'piano-controls.png'))
                window.write_audio(out/'piano.csv')
                (out/'result.json').write_text(json.dumps(dict(result='PASS',source=window.engine.source,voices=window.engine.voices,piano_settings=window.engine.piano_settings),ensure_ascii=False,indent=2),encoding='utf-8')
            except Exception as exc:
                (out/'result.json').write_text(json.dumps(dict(result='FAIL',error=str(exc)),ensure_ascii=False),encoding='utf-8');window.close();app.exit(1);return
            window.close()
        C.QTimer.singleShot(1500,finish_piano)
    if args.live_smoke:
        C.QTimer.singleShot(500,window.toggle_live)
        def live_finish():
            out=Path(args.live_smoke);out.mkdir(parents=True,exist_ok=True)
            try:
                window.stop_live();window.live_view.setCurrentIndex(1);window.refresh()
                assert window.engine.audio_count>=3
                assert window.engine.audio.shape==(512,5)
                window.write_history(out/'滚动历史.csv');window.write_audio(out/'最近一段.csv')
                window.grab().save(str(out/'滚动历史.png'))
                count=window.engine.audio_count;window.clear_waveforms();window.service_live()
                assert not window.live_running
                assert all(c.xData is None or not len(c.xData) for c in window.curves)
                (out/'result.json').write_text(json.dumps(dict(result='PASS',source='模拟',segments=count,points=512)),encoding='utf-8')
            finally:window.close()
        C.QTimer.singleShot(4200,live_finish)
    if args.agent_smoke:
        import subprocess
        out=Path(args.agent_smoke);out.mkdir(parents=True,exist_ok=True)
        window.start_agent()
        command=[str(ROOT/'TangLabCtl.exe')] if getattr(sys,'frozen',False) else [sys.executable,str(ROOT/'tanglabctl.py')]
        log=(out/'cli-result.json').open('w',encoding='utf-8')
        child=subprocess.Popen(command+['--session',str(window.agent.session_path),'run','test.two_voice_spi','--json','{"simulation":true}'],
                               stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        deadline=time.monotonic()+45
        def check_agent_child():
            if child.poll() is None and time.monotonic()<deadline:return
            if child.poll() is None:child.kill();child.wait()
            log.close();window.agent_check_timer.stop();window.refresh()
            for i in range(window.tabs.count()):window.tabs.setCurrentIndex(i);app.processEvents();window.grab().save(str(out/f'page-{i}.png'))
            (out/'joint-check.json').write_text(json.dumps(dict(cli_exit_code=child.returncode,qt_cancel=C.QCoreApplication.translate('QPlatformTheme','Cancel')),ensure_ascii=False),encoding='utf-8')
            window.close()
        window.agent_check_timer=C.QTimer(window);window.agent_check_timer.timeout.connect(check_agent_child);window.agent_check_timer.start(100)
    if args.smoke:
        def finish():
            out=Path(args.smoke);out.mkdir(parents=True,exist_ok=True)
            try:
                for i in range(window.tabs.count()):window.tabs.setCurrentIndex(i);app.processEvents();window.grab().save(str(out/f'page-{i}.png'))
                window.tabs.setCurrentIndex(0);window.cursor_channel.setCurrentIndex(2);window.time_cursor.setChecked(True);window.amp_cursor.setChecked(True);window.focus_wave(2);app.processEvents();window.grab().save(str(out/'cursors.png'))
                window.focus_wave(None);window.time_cursor.setChecked(False);window.amp_cursor.setChecked(False)
                np.savetxt(out/'spectrum.csv',np.column_stack(window.spectrum_data),delimiter=',',header='frequency_Hz,amplitude_dBFS,phase_deg')
                window.write_audio(out/'audio.csv');window.engine.start_record(out/'recording');window.engine.stop_record()
                (out/'smoke.json').write_text(json.dumps(dict(audio_shape=list(window.engine.audio.shape),stats=window.engine.stats()),ensure_ascii=False,indent=2),encoding='utf-8')
            finally:window.close()
        C.QTimer.singleShot(2200,finish)
    return app.exec()

if __name__=='__main__':sys.exit(main())
