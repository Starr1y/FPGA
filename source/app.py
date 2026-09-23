from lab_ui import ChineseViewBox,setup_plot,chinese_qt,REPORTS
import argparse
import json
import math
import sys
import time
from pathlib import Path
import numpy as np
import pyqtgraph as pg
from PySide6 import QtCore,QtGui,QtWidgets as W
from engine import Engine
from protocol import euler,from_euler,relative,rotation_matrix

ROOT=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent

class PoseView(W.QWidget):
    def __init__(self):
        super().__init__(); self.q=(0,0,0,1); self.valid=False; self.setMinimumSize(500,340)
    def paintEvent(self,event):
        p=QtGui.QPainter(self); p.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)
        p.fillRect(self.rect(),QtGui.QColor('#111c2c'))
        m=np.array(rotation_matrix(self.q)); scale=min(self.width(),self.height())*.27
        # Fixed oblique camera, orthographic projection; the sensor itself rotates in 3D.
        camera=np.array([[.82,-.57,0],[.25,.36,-.9],[.51,.74,.44]])
        def project(v):
            r=camera@m@np.array(v)
            return QtCore.QPointF(self.width()/2+r[0]*scale,self.height()/2+r[1]*scale),r[2]
        vertices=[(x,y,z) for x in (-1,1) for y in (-.65,.65) for z in (-.12,.12)]
        faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
        for face in sorted(faces,key=lambda f:sum(project(vertices[i])[1] for i in f)):
            p.setPen(QtGui.QPen(QtGui.QColor('#70e2d2'),1.5))
            p.setBrush(QtGui.QColor('#1e716f') if face!=(1,5,7,3) else QtGui.QColor('#34b9a3'))
            p.drawPolygon(QtGui.QPolygonF([project(vertices[i])[0] for i in face]))
        origin=project((0,0,0))[0]
        for v,color,label in [((1.6,0,0),'#ff7979','X'),((0,1.6,0),'#71e69d','Y'),((0,0,1.6),'#77adff','Z')]:
            end=project(v)[0]; p.setPen(QtGui.QPen(QtGui.QColor(color),3)); p.drawLine(origin,end); p.drawText(end,label)
        p.setPen(QtGui.QColor('#c2d2e3'))
        p.drawText(18,28,'BNO085 · 三维方向示意（不表示位置）' if self.valid else '等待姿态数据 · 可点击“模拟演示”')
        p.drawText(18,self.height()-18,'坐标约定：Z-Y-X / 偏航-俯仰-横滚；轴向以模块标识为准')

class MainWindow(W.QMainWindow):
    def __init__(self):
        super().__init__(); self.engine=Engine(); self.origin=None; self.current_q=None; self.tick=0
        self.setWindowTitle('BNO085 实验室 · 姿态与串口测试'); self.resize(1240,840)
        self.setStyleSheet('QMainWindow,QWidget{background:#111c2c;color:#dbe7f3;font-size:14px;} '
            'QPushButton{background:#24445b;padding:8px;border-radius:5px;} QPushButton:hover{background:#32617b;}'
            'QComboBox,QSpinBox{background:#213247;padding:5px;} QTabBar::tab{padding:12px;background:#1b2b40;}'
            'QTabBar::tab:selected{background:#245b63;} QGroupBox{border:1px solid #395068;margin-top:12px;padding-top:12px;}'
            'QPushButton:disabled,QComboBox:disabled{color:#65778b;} QPlainTextEdit{background:#142337;}')
        central=W.QWidget(); self.setCentralWidget(central); layout=W.QVBoxLayout(central)
        header=W.QHBoxLayout(); title=W.QLabel('BNO085  /  传感器实验室'); title.setStyleSheet('font-size:23px;font-weight:bold;color:#70e2d2;')
        header.addWidget(title); header.addStretch()
        for text,callback in [('模拟演示',self.simulate),('打开回放',self.replay),('使用说明',lambda:QtGui.QDesktopServices.openUrl(QtCore.QUrl.fromLocalFile(str(ROOT/'使用说明.md'))))]:
            b=W.QPushButton(text); b.clicked.connect(callback); header.addWidget(b)
        layout.addLayout(header)
        self.banner=W.QLabel('就绪 · 所有软件统计均不等于物理动作到音频的真实延迟'); layout.addWidget(self.banner)
        self.tabs=W.QTabWidget(); layout.addWidget(self.tabs)
        self.build_connection(); self.build_pose(); self.build_plots(); self.build_stats()
        self.timer=QtCore.QTimer(self); self.timer.timeout.connect(self.refresh); self.timer.start(16)
        self.refresh_ports()
    def button(self,text,callback,layout):
        b=W.QPushButton(text); b.clicked.connect(callback); layout.addWidget(b); return b
    def combo(self,items):
        c=W.QComboBox(); c.addItems(items); return c
    def build_connection(self):
        page=W.QWidget(); l=W.QVBoxLayout(page); row=W.QHBoxLayout()
        self.port=W.QComboBox(); self.proto=self.combo(['UART-RVC','UART-SHTP'])
        row.addWidget(W.QLabel('串口')); row.addWidget(self.port,1); self.button('刷新',self.refresh_ports,row)
        row.addWidget(self.proto); self.connect_btn=self.button('连接',self.connect_serial,row); self.button('断开',self.disconnect,row); l.addLayout(row)
        self.wiring=W.QLabel(); self.wiring.setWordWrap(True); l.addWidget(self.wiring)
        self.device=W.QLabel('设备：尚未读取'); l.addWidget(self.device)
        self.configbox=W.QGroupBox('SHTP 报告设置 · 更改后点击应用'); f=W.QFormLayout(self.configbox)
        self.mode=self.combo(['稳定姿态四元数','姿态四元数','游戏姿态四元数'])
        self.pose_hz=self.combo(['25','50','100','200','400']); self.pose_hz.setCurrentText('100')
        self.acc_hz=self.combo(['50','100','200','250','500']); self.acc_hz.setCurrentText('100')
        self.gyro_hz=self.combo(['关闭','50','100','200','400']); self.linear_hz=self.combo(['关闭','50','100','200','400'])
        for name,widget in [('姿态模式',self.mode),('姿态报告 Hz',self.pose_hz),('加速度报告 Hz',self.acc_hz),('角速度报告 Hz',self.gyro_hz),('线性加速度 Hz',self.linear_hz)]: f.addRow(name,widget)
        r=W.QHBoxLayout(); self.button('200 Hz 姿态＋500 Hz 加速度',self.preset,r); self.apply_btn=self.button('应用配置',self.apply,r); f.addRow(r)
        l.addWidget(self.configbox)
        self.configtext=W.QPlainTextEdit(); self.configtext.setReadOnly(True); l.addWidget(self.configtext,1)
        self.proto.currentTextChanged.connect(self.update_controls); self.update_controls()
        self.tabs.addTab(page,'01  连接与配置')
    def build_pose(self):
        page=W.QWidget(); l=W.QVBoxLayout(page); row=W.QHBoxLayout()
        self.relative_check=W.QCheckBox('使用软件归中后的相对姿态'); row.addWidget(self.relative_check)
        self.button('以当前方向归中',self.recenter,row); self.button('清除归中',self.clear_origin,row); l.addLayout(row)
        self.pose=PoseView(); l.addWidget(self.pose,1)
        self.angles=W.QLabel('偏航 —     俯仰 —     横滚 —'); self.angles.setStyleSheet('font-size:25px;color:#70e2d2;'); l.addWidget(self.angles)
        self.quat=W.QLabel('四元数 x / y / z / w：—'); l.addWidget(self.quat)
        self.accuracy=W.QLabel('精度状态：—'); l.addWidget(self.accuracy)
        self.tabs.addTab(page,'02  姿态显示')
    def build_plots(self):
        page=W.QWidget(); l=W.QVBoxLayout(page); l.addWidget(W.QLabel('曲线显示最近 10 秒；角度为绝对姿态。显示抽取不影响采集记录。'))
        self.plots=[]; self.lines=[]
        for title,unit,names in [('角度','°',['偏航','俯仰','横滚']),('加速度（含重力）','m/s²',['X','Y','Z']),('角速度','rad/s',['X','Y','Z'])]:
            p=pg.PlotWidget(title=title,viewBox=ChineseViewBox()); p.setBackground('#111c2c'); setup_plot(p); p.addLegend(); p.setLabel('left',unit); p.setLabel('bottom','会话时间','s'); p.showGrid(x=True,y=True,alpha=.15)
            self.lines.append([p.plot(pen=pg.mkPen(color,width=1.5),name=name) for color,name in zip(['#ff7979','#71e69d','#77adff'],names)])
            self.plots.append(p); l.addWidget(p)
        self.tabs.addTab(page,'03  实时曲线')
    def build_stats(self):
        page=W.QWidget(); l=W.QVBoxLayout(page); row=W.QHBoxLayout()
        self.record_btn=self.button('开始记录',self.record,row); self.button('停止记录',self.stop_record,row)
        self.button('导出当前统计 JSON',self.export_stats,row); l.addLayout(row)
        self.record_label=W.QLabel('未记录'); l.addWidget(self.record_label)
        self.stats=W.QPlainTextEdit(); self.stats.setReadOnly(True); l.addWidget(self.stats,2)
        self.hist=pg.PlotWidget(title='PC 接收批次间隔分布（不是传感器延迟）',viewBox=ChineseViewBox()); self.hist.setBackground('#111c2c'); setup_plot(self.hist); self.hist.setLabel('bottom','间隔','ms')
        self.histline=self.hist.plot(pen='#70e2d2'); l.addWidget(self.hist,1)
        l.addWidget(W.QLabel('传感器相对偏移不直接跨包当作绝对时钟；真实动作延迟需要外部同步测量。'))
        self.tabs.addTab(page,'04  性能与记录')
    def error(self,exc): W.QMessageBox.warning(self,'操作未完成',str(exc))
    def refresh_ports(self):
        from serial.tools.list_ports import comports
        old=self.port.currentData(); self.port.clear()
        for p in comports(): self.port.addItem(f'{p.device} · {p.description}',p.device)
        i=self.port.findData(old)
        if i>=0: self.port.setCurrentIndex(i)
    def update_controls(self):
        shtp=self.proto.currentText()=='UART-SHTP'
        self.configbox.setEnabled(shtp)
        self.wiring.setText(('PS1=1，PS0=0；3,000,000 baud，8N1。TX↔RX，共地；需模块外部时钟/晶振。' if shtp else
            'PS1=0，PS0=1；115,200 baud，8N1；固定 100 Hz。BNO TX→转换器 RX，共地。')+
            '\n切换：断开软件 → 断电修改跳线 → 上电 → 选择协议 → 连接。仅使用匹配的 3.3V 逻辑。')
    def connect_serial(self):
        try:
            if not self.port.currentData(): raise ValueError('未发现串口，请连接 USB 转 TTL 并安装驱动')
            self.engine.connect(self.port.currentData(),self.proto.currentText()); self.origin=None; self.current_q=None
        except Exception as exc: self.error(exc)
    def disconnect(self): self.engine.disconnect()
    def simulate(self):
        self.engine.simulate(); self.proto.setCurrentText('UART-SHTP'); self.origin=None; self.current_q=None; self.tabs.setCurrentIndex(1)
    def replay(self):
        path=W.QFileDialog.getExistingDirectory(self,'选择包含 metadata.json 和 raw.jsonl 的记录目录',str(ROOT/'recordings'))
        if path:
            try:
                self.engine.replay(path); self.proto.setCurrentText(self.engine.protocol); self.origin=None; self.current_q=None
            except Exception as exc: self.error(exc)
    def preset(self): self.pose_hz.setCurrentText('200'); self.acc_hz.setCurrentText('500')
    def apply(self):
        try:
            chosen=[0x28,5,8][self.mode.currentIndex()]
            settings={rid:(int(self.pose_hz.currentText()) if rid==chosen else 0) for rid in (5,8,0x28)}
            settings.update({1:int(self.acc_hz.currentText()),2:int(self.gyro_hz.currentText()) if self.gyro_hz.currentText()!='关闭' else 0,
                             4:int(self.linear_hz.currentText()) if self.linear_hz.currentText()!='关闭' else 0})
            self.engine.apply_config(settings)
        except Exception as exc: self.error(exc)
    def recenter(self):
        if self.current_q is None: self.error('尚无有效姿态'); return
        self.origin=self.current_q; self.relative_check.setChecked(True)
    def clear_origin(self): self.origin=None; self.relative_check.setChecked(False)
    def record(self):
        try:
            path=ROOT/'recordings'/time.strftime('%Y%m%d-%H%M%S')
            self.engine.start_recording(path); self.record_label.setText(str(path))
        except Exception as exc: self.error(exc)
    def stop_record(self):
        try: self.engine.stop_recording(); self.record_label.setText('记录已关闭；文件保留在 recordings')
        except Exception as exc: self.error(exc)
    def clean_stats(self,s): return {k:v for k,v in s.items() if k not in ('latest','history','batch_values')}
    def export_stats(self):
        path,_=W.QFileDialog.getSaveFileName(self,'导出统计',str(ROOT/'统计.json'),'JSON (*.json)')
        if path:
            try: Path(path).write_text(json.dumps(self.clean_stats(self.engine.snapshot()),ensure_ascii=False,indent=2),encoding='utf-8')
            except Exception as exc: self.error(exc)
    def refresh(self):
        s=self.engine.snapshot(); self.tick+=1
        self.banner.setText(f"{s['source']}  ·  {s['status']}  |  软件统计不代表真实动作延迟")
        self.proto.setEnabled(not self.engine.running); self.connect_btn.setEnabled(not self.engine.running)
        self.apply_btn.setEnabled(self.engine.running and s['source'].startswith('串口') and not s['pending'])
        self.device.setText('设备：'+s['device'])
        candidates=[v for k,v in s['latest'].items() if k in ('rvc','rotation','game','stabilized')]
        if candidates:
            ns,report=max(candidates,key=lambda pair:pair[0]); q=from_euler(*report.values[:3]) if report.kind=='rvc' else report.values
            self.current_q=q
            display=relative(q,self.origin) if self.relative_check.isChecked() and self.origin else q
            self.pose.q=display; self.pose.valid=True; self.pose.update()
            y,p,r=euler(display); self.angles.setText(f'偏航  {y:+7.2f}°     俯仰  {p:+7.2f}°     横滚  {r:+7.2f}°')
            suffix='（由 RVC 欧拉角重建）' if report.kind=='rvc' else ''
            self.quat.setText('四元数 x/y/z/w：'+'  /  '.join(f'{v:+.5f}' for v in display)+suffix)
            age=(time.perf_counter_ns()-ns)/1e6
            self.accuracy.setText(f'精度状态：{report.accuracy if report.accuracy is not None else "RVC 不提供"}；距最近姿态接收 {age:.0f} ms（不是传感器延迟）')
        else:
            self.current_q=None; self.pose.valid=False; self.pose.update(); self.angles.setText('偏航 —     俯仰 —     横滚 —'); self.quat.setText('四元数：—'); self.accuracy.setText('精度状态：—')
        if self.tick%6: return
        with self.engine.lock:
            if s['last_data_ns']: self.engine.ui_ms.append((time.perf_counter_ns()-s['last_data_ns'])/1e6)
        names={1:'加速度',2:'角速度',4:'线性加速度',5:'姿态',8:'游戏姿态',0x28:'稳定姿态'}
        rows=['报告：请求 Hz / 返回 Hz / 配置状态（实际接收速率见性能页）']
        for rid,hz in s['desired'].items():
            v=s['confirmed'].get(rid); rate='—' if v is None else ('关闭' if v==0 else f'{1e6/v:.2f}')
            state=s['failures'].get(rid,'等待应答' if rid in s['pending'] else ('收到配置' if v is not None else '排队'))
            rows.append(f'{names.get(rid,rid)}：{hz} / {rate} / {state}')
        rows+=['','最近设备事件：']+s['events'][-8:]
        self.configtext.setPlainText('\n'.join(rows))
        lines=[f"数据来源：{s['source']}", '报告平均接收速率（从本次会话开始统计）：']
        lines += [f'  {REPORTS.get(k,k)}: {v:.2f} Hz，累计 {s["counts"].get(k,0)}' for k,v in s['rates'].items()]
        lines += ['报告序号不连续事件（不等于精确丢帧数）：'+('，'.join(f'{REPORTS.get(k,k)} {v}' for k,v in s['gaps'].items()) or '无'),
                  f'传输序号异常：{s["transport_gaps"]}；解析错误：{s["parse_errors"]}；未处理控制帧：{s["unsupported_controls"]}',
                  'P50 / P95 / P99 / 最大值，单位 ms：',f'  PC 接收批次间隔：{s["batch_ms"]}',
                  f'  批次解析与入队耗时：{s["parse_ms"]}',f'  最新样本接收至界面提交年龄：{s["ui_ms"]}',
                  f'偏航 累计变化 {s["yaw_change"]:+.3f}°，展开后范围 {s["yaw_range"]:.3f}°（仅静止时解释为漂移）',
                  f'记录队列丢弃：{s["recorder_dropped"]}；记录错误：{s["recorder_error"] or "无"}',
                  '曲线缓存滚动保留 30,000 条；不等于记录丢弃。',
                  '传感器绝对采样周期：当前后端无可靠跨包同步时间，未统计。']
        self.stats.setPlainText('\n'.join(lines))
        if s['batch_values']:
            counts,edges=np.histogram(s['batch_values'],bins=35); self.histline.setData((edges[1:]+edges[:-1])/2,counts)
        history=s['history']
        if history:
            end=history[-1][0]; start=history[0][0]; grouped=[[],[],[]]
            for ns,v in history:
                if ns<end-10e9: continue
                t=(ns-start)/1e9
                if v.kind in ('rvc','rotation','game','stabilized'):
                    grouped[0].append((t,v.values[:3] if v.kind=='rvc' else euler(v.values)))
                if v.kind in ('rvc','accel'): grouped[1].append((t,v.values[3:] if v.kind=='rvc' else v.values))
                if v.kind=='gyro': grouped[2].append((t,v.values))
            for index,g in enumerate(grouped):
                if len(g)>2000: g=g[::math.ceil(len(g)/2000)]
                for axis,line in enumerate(self.lines[index]): line.setData([v[0] for v in g],[v[1][axis] for v in g])
                self.plots[index].setTitle(['角度','加速度（含重力）','角速度'][index]+(' · 暂无可用报告' if not g else ''))
        else:
            for group in self.lines:
                for line in group: line.setData([],[])
    def closeEvent(self,event):
        self.timer.stop(); self.engine.disconnect(); event.accept()

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--demo',action='store_true'); parser.add_argument('--smoke',action='store_true')
    args=parser.parse_args(); app=W.QApplication(sys.argv);chinese_qt(app)
    # Qt offscreen on Windows may not enumerate system fonts; explicitly register locally.
    font_path=Path('C:/Windows/Fonts/msyh.ttc')
    if font_path.is_file():
        fid=QtGui.QFontDatabase.addApplicationFont(str(font_path))
        families=QtGui.QFontDatabase.applicationFontFamilies(fid)
        app.setFont(QtGui.QFont(families[0] if families else 'Microsoft YaHei UI',10))
    window=MainWindow(); window.show()
    if args.demo or args.smoke: window.simulate()
    if args.smoke:
        def finish():
            try:
                out=ROOT/'evidence'/f'gui-{time.time_ns()}'
                out.mkdir(parents=True)
                for i in range(4):
                    window.tabs.setCurrentIndex(i); app.processEvents()
                    if not window.grab().save(str(out/f'界面-{i+1}.png')): raise OSError('截图保存失败')
                s=window.engine.snapshot()
                (out/'gui_smoke.json').write_text(json.dumps(window.clean_stats(s),ensure_ascii=False,indent=2),encoding='utf-8')
                print('GUI_EVIDENCE='+str(out))
            finally: window.close()
        QtCore.QTimer.singleShot(3500,finish)
    return app.exec()

if __name__=='__main__': sys.exit(main())
