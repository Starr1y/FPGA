"""Chinese plot interactions and complete-capture spectrum analysis."""
from pathlib import Path
import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore as C,QtWidgets as W

CHANNELS=['声部一','声部二','声部三','声部四','混音']
REPORTS={'rvc':'RVC 姿态与加速度','rotation':'姿态四元数','game':'游戏姿态四元数',
         'stabilized':'稳定姿态四元数','accel':'加速度','gyro':'角速度','linear':'线性加速度'}

def chinese_qt(app):
    from PySide6 import QtGui as G
    import os
    font_path=Path(os.environ.get('WINDIR','C:/Windows'))/'Fonts/msyh.ttc'
    if font_path.is_file():
        font_id=G.QFontDatabase.addApplicationFont(str(font_path))
        families=G.QFontDatabase.applicationFontFamilies(font_id)
        if families:app.setFont(G.QFont(families[0],9))
    C.QLocale.setDefault(C.QLocale('zh_CN'))
    app.setAttribute(C.Qt.ApplicationAttribute.AA_DontUseNativeDialogs,True)
    translator=C.QTranslator(app)
    if translator.load('qtbase_zh_CN',C.QLibraryInfo.path(C.QLibraryInfo.LibraryPath.TranslationsPath)):
        app.installTranslator(translator)
    app.chinese_translator=translator

def spectrum(samples,fs):
    x=np.asarray(samples,dtype=float)/32768
    n=len(x)
    if n<4 or fs<=0:raise ValueError('完整采样不足，无法分析')
    window=np.hanning(n);z=np.fft.rfft(x*window)
    amplitude=np.abs(z)/window.sum();amplitude[1:]*=2
    if n%2==0:amplitude[-1]/=2
    db=20*np.log10(np.maximum(amplitude,1e-12))
    phase=np.angle(z,deg=True)
    valid=amplitude>max(float(amplitude.max())*.001,1e-12)
    phase[~valid]=np.nan
    return np.fft.rfftfreq(n,1/fs),db,phase

class ChineseViewBox(pg.ViewBox):
    selected=C.Signal()
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs);self.plot=None;self.cursor_menu=None;self.grid=True
    def mouseClickEvent(self,event):
        if event.button()==C.Qt.MouseButton.LeftButton:
            event.accept();self.selected.emit()
        else:super().mouseClickEvent(event)
    def getContextMenus(self,event):return []
    def raiseContextMenu(self,event):
        self.context_menu=self.make_menu();self.context_menu.popup(event.screenPos().toPoint());event.accept()
    def make_menu(self):
        menu=W.QMenu()
        menu.addAction('自动适应数据',lambda:self.enableAutoRange())
        menu.addAction('重置缩放',lambda:self.enableAutoRange())
        menu.addAction('鼠标拖动：平移',lambda:self.setMouseMode(self.PanMode))
        menu.addAction('鼠标拖动：框选放大',lambda:self.setMouseMode(self.RectMode))
        grid=menu.addAction('显示网格');grid.setCheckable(True);grid.setChecked(self.grid)
        grid.toggled.connect(self.set_grid)
        if self.cursor_menu:self.cursor_menu(menu)
        menu.addSeparator();menu.addAction('导出图片…',self.export_image)
        return menu
    def set_grid(self,checked):
        self.grid=checked
        if self.plot:self.plot.showGrid(x=checked,y=checked,alpha=.15)
    def export_image(self):
        from pyqtgraph.exporters import ImageExporter
        path,_=W.QFileDialog.getSaveFileName(None,'导出当前图表','图表.png','PNG 图片 (*.png)')
        if path:
            try:ImageExporter(self.plot).export(path)
            except Exception as exc:W.QMessageBox.warning(None,'导出失败',str(exc))

def setup_plot(plot):
    if hasattr(plot,'plotItem'):plot=plot.plotItem
    vb=plot.getViewBox();vb.plot=plot
    plot.setMenuEnabled(False,enableViewBoxMenu=True);plot.hideButtons()
    plot.showGrid(x=True,y=True,alpha=.15)
    plot.getAxis('left').setWidth(82)
    if plot.scene() is not None:plot.scene().contextMenu=[]
    return plot

class AnalysisMixin:
    def init_cursors(self,layout):
        self.cursor_state=[dict(time=False,amplitude=False,positions=[5.,15.,-1000.,1000.]) for _ in CHANNELS]
        self.cursor_lines=[]
        row=W.QHBoxLayout();row.addWidget(W.QLabel('游标声部'))
        self.cursor_channel=W.QComboBox();self.cursor_channel.addItems(CHANNELS);row.addWidget(self.cursor_channel)
        self.time_cursor=W.QCheckBox('时间游标');self.amp_cursor=W.QCheckBox('幅值游标')
        row.addWidget(self.time_cursor);row.addWidget(self.amp_cursor)
        self.button(row,'复位本路游标',self.reset_cursors);row.addStretch();layout.addLayout(row)
        self.cursor_channel.setToolTip('选择要设置和读取游标的声部。分栏模式可同时开启多路；叠加模式仅显示所选声部。')
        self.time_cursor.setToolTip('开启两条竖线，拖动测量时间差；再次取消即可关闭。')
        self.amp_cursor.setToolTip('开启两条横线，拖动测量幅值差，单位为 PCM。')
        self.cursor_channel.currentIndexChanged.connect(self.sync_cursor_controls)
        self.time_cursor.toggled.connect(lambda value:self.set_cursor_flag('time',value))
        self.amp_cursor.toggled.connect(lambda value:self.set_cursor_flag('amplitude',value))
    def mount_cursors(self):
        self.cursor_lines=[]
        for channel,state in enumerate(self.cursor_state):
            plot=self.plots[channel if self.stacked.isChecked() else 0];lines=[]
            for k,pos in enumerate(state['positions']):
                line=pg.InfiniteLine(pos=pos,angle=90 if k<2 else 0,movable=True,
                                     pen=pg.mkPen('#ffd166' if k<2 else '#f59ac2',width=1.5),
                                     label=('时间' if k<2 else '幅值')+str(k%2+1)+'：{value:.2f}')
                plot.addItem(line,ignoreBounds=True)
                line.sigPositionChanged.connect(lambda obj,c=channel,j=k:self.cursor_moved(c,j,obj.value()))
                lines.append(line)
            self.cursor_lines.append(lines)
        for i,p in enumerate(self.plots):
            p.getViewBox().cursor_menu=lambda menu,c=i:self.add_cursor_menu(menu,c if self.stacked.isChecked() else self.cursor_channel.currentIndex())
        self.sync_cursor_controls()
    def cursor_moved(self,channel,k,value):
        self.cursor_state[channel]['positions'][k]=value
        self.cursor_channel.setCurrentIndex(channel);self.update_cursor_readout()
    def sync_cursor_controls(self,*args):
        state=self.cursor_state[self.cursor_channel.currentIndex()]
        for w,key in [(self.time_cursor,'time'),(self.amp_cursor,'amplitude')]:
            w.blockSignals(True);w.setChecked(state[key]);w.blockSignals(False)
        selected=self.cursor_channel.currentIndex()
        for i,lines in enumerate(self.cursor_lines):
            for j,line in enumerate(lines):line.setVisible(self.cursor_state[i]['time' if j<2 else 'amplitude'] and (self.stacked.isChecked() or selected==i))
        self.update_cursor_readout()
    def set_cursor_flag(self,key,value,channel=None):
        channel=self.cursor_channel.currentIndex() if channel is None else channel
        self.cursor_state[channel][key]=value;self.cursor_channel.setCurrentIndex(channel);self.sync_cursor_controls()
    def reset_cursors(self):
        c=self.cursor_channel.currentIndex();plot=self.plots[c if self.stacked.isChecked() else 0]
        (x0,x1),(y0,y1)=plot.getViewBox().viewRange()
        for line,value in zip(self.cursor_lines[c],[x0+(x1-x0)/3,x0+2*(x1-x0)/3,y0+(y1-y0)/3,y0+2*(y1-y0)/3]):line.setValue(value)
        self.update_cursor_readout()
    def add_cursor_menu(self,menu,channel):
        sub=menu.addMenu(CHANNELS[channel]+'游标')
        for key,label in [('time','时间游标'),('amplitude','幅值游标')]:
            action=sub.addAction(label);action.setCheckable(True);action.setChecked(self.cursor_state[channel][key])
            action.toggled.connect(lambda checked,k=key,c=channel:self.set_cursor_flag(k,checked,c))
        def reset():self.cursor_channel.setCurrentIndex(channel);self.reset_cursors()
        sub.addAction('复位本路游标',reset)
    def update_cursor_readout(self):
        if not hasattr(self,'cursors'):return
        c=self.cursor_channel.currentIndex();s=self.cursor_state[c];t1,t2,y1,y2=s['positions'];dt=abs(t2-t1)
        text=[CHANNELS[c]]
        if s['time']:text.append(f'时间1 {t1:.3f} ms / 时间2 {t2:.3f} ms / 时间差 {dt:.3f} ms / '+(f'对应频率 {1000/dt:.2f} Hz' if dt>1e-12 else '两线重合'))
        if s['amplitude']:text.append(f'幅值1 {y1:.1f} PCM / 幅值2 {y2:.1f} PCM / 幅值差 {abs(y2-y1):.1f} PCM')
        if len(text)==1:text.append('游标已关闭；可在上方勾选或右键开启。')
        self.cursors.setText('  |  '.join(text))
    def spectrum_page(self):
        layout=self.page('06  频谱分析');row=W.QHBoxLayout();row.addWidget(W.QLabel('分析声部'))
        self.spectrum_channel=W.QComboBox();self.spectrum_channel.addItems(CHANNELS);self.spectrum_channel.setCurrentIndex(4);row.addWidget(self.spectrum_channel)
        self.button(row,'导出幅相谱 CSV',self.export_spectrum);row.addStretch();layout.addLayout(row)
        self.spectrum_note=W.QLabel('等待完整采样');layout.addWidget(self.spectrum_note)
        self.spectrum_plots=[];self.spectrum_curves=[]
        for title,label,unit in [('幅度谱 · 汉宁窗','幅度','dBFS'),('相位谱 · 以抓取起点为参考','相位','°')]:
            plot=pg.PlotWidget(title=title,viewBox=ChineseViewBox());plot.setBackground('#111c2c');setup_plot(plot)
            plot.setLabel('bottom','频率',units='Hz');plot.setLabel('left',label,units=unit)
            self.spectrum_plots.append(plot);self.spectrum_curves.append(plot.plot(pen='#53dfc2',connect='finite',symbol='o' if unit=='°' else None,symbolSize=4));layout.addWidget(plot,1)
        self.spectrum_plots[1].setYRange(-180,180,padding=0)
        note=W.QLabel('只分析完整样本；低于峰值 60 dB 的频点不显示相位。相位不是接口延迟。\n幅度以满幅正弦峰值为 0 dBFS；相位以余弦为 0°，正弦为 −90°。');note.setWordWrap(True);layout.addWidget(note)
        self.spectrum_channel.setToolTip('选择四个声部中的一路或混音，使用最近一次完整抓取/回放数据。')
        self.spectrum_channel.currentIndexChanged.connect(lambda _:self.update_spectrum(force=True))
        self.spectrum_key=None;self.spectrum_data=None
    def update_spectrum(self,force=False):
        if getattr(self,'clear_pending',False):return
        if self.pause.isChecked():return
        e=self.engine;key=(e.source,e.audio_revision,self.spectrum_channel.currentIndex(),e.audio is None)
        if key==self.spectrum_key and not force:return
        self.spectrum_key=key
        if e.audio is None:
            self.spectrum_data=None
            for curve in self.spectrum_curves:curve.setData([],[])
            self.spectrum_note.setText('没有完整样本；包络预览不可用于幅相谱，请先抓取 2048 点。');return
        data=e.audio[:,self.spectrum_channel.currentIndex()].copy();f,db,phase=spectrum(data,e.fs);self.spectrum_data=(f,db,phase)
        self.spectrum_curves[0].setData(f,db)
        if np.isfinite(phase).any():self.spectrum_curves[1].setData(f,phase)
        else:self.spectrum_curves[1].setData([],[])
        for plot in self.spectrum_plots:plot.setXRange(0,e.fs/2,padding=0)
        self.spectrum_note.setText(f'{e.source} · {CHANNELS[self.spectrum_channel.currentIndex()]} · 采样率 {e.fs} Hz · {len(data)} 点 · 频率分辨率 {e.fs/len(data):.4f} Hz'+(' · 无有效信号' if not np.any(data) else ''))
    def export_spectrum(self):
        import csv
        self.update_spectrum(force=True)
        if self.spectrum_data is None:raise ValueError('先抓取完整采样，包络不能用于幅相谱')
        path,_=W.QFileDialog.getSaveFileName(self,'导出幅度与相位谱','幅相谱.csv','CSV 文件 (*.csv)')
        if path:
            with Path(path).open('w',encoding='utf-8-sig',newline='') as out:
                writer=csv.writer(out);writer.writerow(['频率_Hz','幅度_dBFS','相位_度'])
                for f,db,phase in zip(*self.spectrum_data):writer.writerow([f,db,'' if np.isnan(phase) else phase])
