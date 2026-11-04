import json,threading,time
from PySide6 import QtCore as C,QtWidgets as W
from lab_agent import CommandController,AgentServer

class UiBridge(C.QObject):
    requested=C.Signal(object)
    def __init__(self,window):
        super().__init__(window);self.window=window;self.requested.connect(self.invoke)
    def call(self,action):
        request=dict(action=action,event=threading.Event());self.requested.emit(request)
        if not request['event'].wait(4):raise TimeoutError('界面响应超时')
        if 'error' in request:raise ValueError(request['error'])
        return request.get('result',{})
    @C.Slot(object)
    def invoke(self,r):
        w=self.window
        try:
            action=r['action']
            if action in ('build','synthesis'):w.build(action=='build')
            elif action=='stop':w.stop_build()
            r['result']=dict(running=w.process.state()!=C.QProcess.ProcessState.NotRunning,
                             exit_code=w.process.exitCode(),log=w.log.toPlainText(),project=w.project.text())
        except Exception as exc:r['error']=str(exc)
        finally:r['event'].set()

class AgentGuiMixin:
    def agent_page(self,root):
        self.bridge=UiBridge(self);self.controller=CommandController(self.engine,root,self.bridge.call);self.agent=AgentServer(self.controller)
        self.last_agent_job=None;self.observed_jobs=set()
        l=self.page('07  agent 调试');l.addWidget(W.QLabel('本机命令接口默认关闭，仅监听 127.0.0.1。Codex / Claude Code 可使用 TangLabCtl.exe。'))
        row=W.QHBoxLayout();self.button(row,'开启本机接口',self.start_agent);self.button(row,'关闭本机接口',self.stop_agent);self.button(row,'复制连接信息',self.copy_agent);l.addLayout(row)
        self.agent_address=W.QLineEdit('未开启');self.agent_address.setReadOnly(True);l.addWidget(self.agent_address)
        self.agent_token=W.QLineEdit();self.agent_token.setReadOnly(True);self.agent_token.setEchoMode(W.QLineEdit.EchoMode.Password);self.agent_token.setPlaceholderText('开启后生成会话令牌');l.addWidget(self.agent_token)
        self.agent_token.setToolTip('每次开启生成新令牌。命令工具自动读取同目录 .agent-session.json，不要分享令牌或会话文件。')
        self.agent_session=W.QLabel('命令示例：TangLabCtl.exe status\n参数文件与上板步骤见《两声部与SPI上板测试指南.txt》。');self.agent_session.setWordWrap(True);l.addWidget(self.agent_session)
        row=W.QHBoxLayout();self.button(row,'取消当前命令',self.cancel_agent_job);self.button(row,'打开测试结果目录',lambda:self.open_file(root/'agent-results'));l.addLayout(row)
        self.agent_progress=W.QLabel('命令队列空闲');l.addWidget(self.agent_progress)
        self.agent_events=W.QPlainTextEdit();self.agent_events.setReadOnly(True);l.addWidget(self.agent_events)
        self.agent_timer=C.QTimer(self);self.agent_timer.timeout.connect(self.refresh_agent);self.agent_timer.start(150)
    def submit_command(self,action,params=None):
        if action in ('connect','disconnect','demo','duo.demo','replay','test.two_voice_spi') and hasattr(self,'live_running'):
            self.stop_live('数据源或测试模式已切换')
        job=self.controller.submit(action,params);self.last_agent_job=job['id']
        if action in ('voices.set','voices.release'):
            self.voice_job_revisions[job['id']]=self.voice_edit_revision
            self.latest_voice_job=job['id'];self.voice_edit_time=time.time()
            self.voice_apply_status.setText('声部参数已排队，等待设备应答。')
        return job
    def start_agent(self):
        info=self.agent.start();self.agent_address.setText(info['url']);self.agent_token.setText(info['token'])
        self.agent_session.setText('会话文件：'+str(self.agent.session_path)+'\n命令工具自动读取该文件；不要把它放入分享包。')
    def stop_agent(self):
        self.agent.stop();self.agent_address.setText('未开启');self.agent_token.clear()
    def copy_agent(self):
        if not self.agent.http:raise ValueError('先开启本机接口')
        W.QApplication.clipboard().setText(json.dumps(self.agent.info,ensure_ascii=False,indent=2))
    def cancel_agent_job(self):
        if self.controller.active:self.controller.cancel(self.controller.active)
    def refresh_agent(self):
        c=self.controller
        with c.lock:
            events=list(c.events);jobs=[c.job(k) for k in c.jobs]
        text='\n'.join(events)
        if self.agent_events.toPlainText()!=text:self.agent_events.setPlainText(text)
        if c.active:
            j=c.job(c.active);self.agent_progress.setText(j['action']+'：'+j['message'])
        else:self.agent_progress.setText('命令队列空闲')
        for j in jobs:
            if j['state'] not in ('completed','failed','cancelled') or j['id'] in self.observed_jobs:continue
            self.observed_jobs.add(j['id'])
            if j['action'] in ('connect','demo','replay'):self.revision=-1
            if j['state']=='failed':self.engine.status='操作失败：'+j['message']
            if j['action'] in ('voices.set','voices.release','connect','demo','test.two_voice_spi'):
                # A delayed completion must never overwrite a newer checkbox/edit.
                # Use this job's confirmed snapshot, not the engine of a later job.
                edit_revision=self.voice_job_revisions.pop(j['id'],None)
                unchanged=(edit_revision==self.voice_edit_revision if edit_revision is not None
                           else self.voice_edit_time<=j['created'])
                latest=edit_revision is None or j['id']==self.latest_voice_job
                if j['state']=='completed' and unchanged and latest:
                    result=j.get('result',{})
                    voices=result.get('voices',self.engine.voices)
                    self.piano_values=[dict(v) for v in result.get('piano_settings',self.engine.piano_settings)]
                    self.show_piano_controls()
                    for i,cells in enumerate(self.controls):
                        for key,w in cells:
                            value=voices[i][key]
                            with C.QSignalBlocker(w):
                                if key=='wave':w.setCurrentIndex(value)
                                elif key=='gate':w.setChecked(value)
                                else:w.setValue(value)
                if j['action'] in ('voices.set','voices.release') and latest:
                    if j['state']=='completed':
                        label='模拟参数已应用（非硬件应答）' if self.engine.source.startswith('模拟') else '声部参数已收到设备应答'
                        self.voice_apply_status.setText(label+('。' if unchanged else '；当前新修改尚未应用。'))
                    else:self.voice_apply_status.setText('声部参数未完整应用：'+j['message']+'；当前编辑已保留。')
            if j['action']=='imu.mode':self.mode.setCurrentIndex(self.engine.mode)
        # Only ids from retained jobs need to be retained here.
        self.observed_jobs.intersection_update({j['id'] for j in jobs})
