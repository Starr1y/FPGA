"""Bounded segmented scope history and nonblocking capture scheduling."""
import csv,time
from pathlib import Path
import numpy as np
from PySide6 import QtWidgets as W

class LiveMixin:
    def live_controls(self,layout):
        self.live_running=False;self.live_job=None;self.live_next=0;self.live_message='已停止'
        self.live_session=self.engine.audio_session;self.clear_pending=False
        row=W.QHBoxLayout()
        self.live_button=self.button(row,'开始连续抓取',self.toggle_live)
        self.live_button.setToolTip('自动重复立即抓取五路完整样本；分段采集，段间有空档。')
        self.capture_size=W.QComboBox();self.capture_size.addItems(['快速 512 点','精确 2048 点']);row.addWidget(self.capture_size)
        self.capture_size.setToolTip('仅影响连续抓取；512点分辨率93.75 Hz，2048点分辨率23.4375 Hz。单次按钮仍抓取2048点。快速模式需要1.3固件。')
        self.capture_cap_key=None
        self.live_view=W.QComboBox();self.live_view.addItems(['最新一段','滚动历史（最近30段）']);row.addWidget(self.live_view)
        self.live_view.currentIndexChanged.connect(self.invalidate_live)
        self.follow_latest=W.QCheckBox('跟随最新');self.follow_latest.setChecked(True);row.addWidget(self.follow_latest)
        self.follow_latest.toggled.connect(self.invalidate_live)
        self.button(row,'导出滚动历史 CSV',self.export_history)
        layout.addLayout(row);self.live_note=W.QLabel('分段采集，段间有空档；等待完整抓取');layout.addWidget(self.live_note)
    def invalidate_live(self,*args):self.revision=-1
    def stop_live(self,message='已停止'):
        self.live_running=False;self.live_message=message;self.live_button.setText('开始连续抓取')
    def toggle_live(self):
        if self.live_running:self.stop_live('已停止；已发出的抓取可完成');return
        if not self.engine.ready:raise ValueError('请先连接 FPGA 或开启模拟演示')
        if self.clear_pending:raise ValueError('正在清理在途数据，请稍候再开始')
        self.live_session=self.engine.audio_session
        self.live_job=self.submit_command('preview',dict(enabled=False))['id']
        self.live_running=True;self.live_message='等待采集';self.live_button.setText('停止连续抓取')
    def service_live(self):
        e=self.engine;c=self.controller
        fast=512 in e.capabilities.get('capture_sizes',[])
        key=(e.audio_session,fast)
        if key!=self.capture_cap_key:
            self.capture_cap_key=key
            self.capture_size.model().item(0).setEnabled(fast)
            self.capture_size.setCurrentIndex(0 if fast else 1)
        with c.lock:
            busy=any(j['state'] in ('queued','running','acknowledged','simulated') for j in c.jobs.values())
            incompatible=any(j['state'] in ('queued','running','acknowledged','simulated') and
                (j['action'] in ('connect','disconnect','demo','replay','test.two_voice_spi') or
                 j['action']=='preview' and j['params'].get('enabled')) for j in c.jobs.values())
        if self.live_running and (incompatible or e.audio_session is not self.live_session):self.stop_live('数据源或模式已切换')
        if self.live_running and not e.ready:self.stop_live('设备已断开')
        if self.live_job:
            j=c.job(self.live_job)
            if j['state'] in ('completed','failed','cancelled'):
                self.live_job=None;self.live_next=time.monotonic()+(.25 if e.source.startswith('模拟') else 0)
                if j['state']!='completed':self.stop_live(j['message'])
                elif j['action']=='capture':self.live_message='完整数据已到达'
        if self.clear_pending:
            if not busy:
                e.clear_waveforms();self.clear_pending=False
            return
        if self.live_running and not busy and not self.live_job and time.monotonic()>=self.live_next:
            self.live_job=self.submit_command('capture',dict(trigger=0,points=512 if self.capture_size.currentIndex()==0 else 2048))['id'];self.live_message='采集中'
        with e.lock:history=list(e.audio_history);count=e.audio_count
        interval=f'{history[-1]["relative"]-history[-2]["relative"]:.2f} 秒' if len(history)>1 else '—'
        self.live_note.setText(f'{self.live_message} · 已完成 {count} 段 · 更新间隔 {interval} · 分段采集，段间有空档')
        with e.lock:diagnostics=list(e.capture_diagnostics)
        if diagnostics:
            d=diagnostics[-1]
            def ms(key):return '尚未完成' if d.get(key) is None else f'{d[key]:.1f} ms'
            self.live_note.setToolTip(f"最近抓取：{d['state']}\n请求至应答：{ms('ack_ms')}\n请求至收齐：{ms('receive_ms')}\n绘图提交耗时：{ms('draw_ms')}\n收齐至绘图（包含暂停等待）：{ms('receive_to_draw_ms')}\nCRC增加：{d.get('crc_delta',0)}；缺包增加：{d.get('missing_delta',0)}\n这些是电脑侧采集诊断，不是传感器或模拟音频延迟。")
    def draw_live(self,a,fs):
        if self.live_view.currentIndex()==0:
            x=np.arange(len(a))/fs*1000
            for i,line in enumerate(self.curves):line.setData(x,a[:,i])
            left,right=0,x[-1]
        else:
            with self.engine.lock:history=list(self.engine.audio_history)
            if not history:return
            xs=[];ys=[]
            for segment in history:
                data=segment['samples'];n=len(data)
                # End aligned with host receive time, NOT a board acquisition timestamp.
                x=segment['relative']*1000-(n-1-np.arange(n))/segment['fs']*1000
                xs.extend((x,np.array([np.nan])));ys.extend((data,np.full((1,5),np.nan)))
            x=np.concatenate(xs);data=np.concatenate(ys)
            for i,line in enumerate(self.curves):line.setData(x,data[:,i],connect='finite')
            left,right=x[0],x[-2]
        label='电脑接收相对时间（非板上测时）' if self.live_view.currentIndex() else '时间'
        for plot in self.plots:
            plot.setLabel('bottom',label,units='ms')
            plot.getAxis('bottom').enableAutoSIPrefix(False)
            if self.follow_latest.isChecked():plot.setXRange(left,max(left+.001,right),padding=.02)
    def write_history(self,path):
        if self.clear_pending:raise ValueError('波形已清空，正在等待在途采集结束')
        with self.engine.lock:history=list(self.engine.audio_history)
        if not history:raise ValueError('没有可导出的完整采样历史')
        with Path(path).open('w',encoding='utf-8-sig',newline='') as out:
            writer=csv.writer(out);writer.writerow(['段编号','段内时间_s','电脑接收Unix时间_s','电脑接收相对时间_s','采样率_Hz','声部一','声部二','声部三','声部四','混音'])
            for segment in history:
                for i,row in enumerate(segment['samples']):writer.writerow([segment['number'],i/segment['fs'],segment['received'],segment['relative'],segment['fs'],*map(int,row)])
    def export_history(self):
        path,_=W.QFileDialog.getSaveFileName(self,'导出滚动历史','滚动历史.csv','CSV 文件 (*.csv)')
        if path:self.write_history(path)
