"""Page09: image/PDF conversion and validated board-owned lesson."""
import json
from pathlib import Path
from PySide6 import QtCore as C,QtWidgets as W
from lab_score import load_score,compile_score,ASSETS
from lab_duo_ui import MouseFan
from lab_score_import import build_import,invalidate,upload_active


def build(g):
    p=W.QWidget();outer=W.QVBoxLayout(p);scroll=W.QScrollArea();scroll.setWidgetResizable(True);body=W.QWidget();col=W.QVBoxLayout(body);scroll.setWidget(body);outer.addWidget(scroll);g.tabs.addTab(p,'09 曲谱上传与教学')
    g.score_answer_job=None;g.score_input=None;g.score_preview=None;g.score_job=None;g.score_seen=-1
    hint=W.QLabel('选择图片／PDF → 格式转换 → 检查转换格式 → 上传；也可导入其他AI转换的JSON文件。\nAI识谱请对照原谱复核。上传成功后选择教学来源，再点击开始；板内曲目断电后需重新上传。实物教学使用S1作答，自动采用目标C档，不需要俯仰换档。');hint.setWordWrap(True);col.addWidget(hint)
    build_import(g,col)
    g.score_summary=W.QLabel('尚未导入曲谱');g.score_summary.setWordWrap(True);col.addWidget(g.score_summary)
    g.score_table=W.QTableWidget(0,8);g.score_table.setHorizontalHeaderLabels(['步骤','手','原音','适配后音','音区','C档','保持ms','前置休止ticks'])
    g.score_table.setAlternatingRowColors(True);g.score_table.verticalHeader().hide();g.score_table.setEditTriggers(W.QAbstractItemView.EditTrigger.NoEditTriggers);g.score_table.horizontalHeader().setSectionResizeMode(W.QHeaderView.ResizeMode.Stretch);g.score_table.setMinimumHeight(170);g.score_table.setMaximumHeight(230);col.addWidget(g.score_table)
    g.score_changes=W.QPlainTextEdit();g.score_changes.setReadOnly(True);g.score_changes.setMaximumHeight(90);col.addWidget(g.score_changes)
    g.score_confirm=W.QCheckBox('我已检查并同意八度／时值适配（有调整时必须确认）');col.addWidget(g.score_confirm)
    advanced=W.QGroupBox('高级选项');advanced.setCheckable(True);advanced.setChecked(False);al=W.QVBoxLayout(advanced);ab=W.QWidget();ac=W.QVBoxLayout(ab);al.addWidget(ab);ab.hide();advanced.toggled.connect(ab.setVisible)
    row=W.QHBoxLayout()
    def button(text,fn):
        b=W.QPushButton(text);b.clicked.connect(lambda:g.safe(fn));row.addWidget(b);return b
    g.score_layout=W.QComboBox();g.score_layout.addItems(['自动：自然音七区／含半音十二区','七音区','五音区','十二音区']);row.addWidget(g.score_layout)
    def layout_changed():
        if g.score_worker:g.score_worker.cancel()
        g.score_converting=False;g.score_convert_button.setText('格式转换');invalidate(g)
    g.score_layout.currentIndexChanged.connect(layout_changed)
    button('载入示例',lambda:set_score(g,load_score(ASSETS/'左右手练习.tangscore.json')))
    button('曲谱模拟（非实物）',lambda:g.submit_command('score.demo'));ac.addLayout(row)
    row=W.QHBoxLayout()
    def export():
        if not g.score_preview:raise ValueError('请先检查转换格式')
        path,_=W.QFileDialog.getSaveFileName(g,'导出适配曲谱','适配曲谱.tangscore.json','TangLab曲谱 (*.tangscore.json)')
        if path:Path(path).write_text(json.dumps(g.score_preview['adapted'],ensure_ascii=False,indent=2),encoding='utf-8')
    button('导出适配后文件',export)
    button('取消上传',lambda:g.controller.cancel(g.score_job) if g.score_job else None)
    button('读取板上曲目状态',lambda:g.submit_command('score.status'))
    button('打开格式规范',lambda:g.open_file(ASSETS/'曲谱格式规范.md'));ac.addLayout(row);col.addWidget(advanced)
    g.score_progress=W.QProgressBar();g.score_progress.setRange(0,100);col.addWidget(g.score_progress)
    g.score_status=W.QLabel('请先连接设备并检查曲谱。');g.score_status.setWordWrap(True);col.addWidget(g.score_status)
    row=W.QHBoxLayout();g.score_source=W.QComboBox();g.score_source.addItems(['真实IMU脱机教学','键盘数字／鼠标教学测试']);row.addWidget(g.score_source)
    button('选择导入曲目与来源（先停止）',lambda:g.submit_command('lesson.configure',dict(source='mouse' if g.score_source.currentIndex() else 'imu',lesson=3)))
    for text,action in [('开始','start'),('暂停','pause'),('继续','resume'),('重来','restart'),('停止','stop')]:button(text,lambda a=action:g.submit_command('lesson.control',{'action':a}))
    col.addLayout(row);g.score_target=W.QLabel('目标：等待板上读回');col.addWidget(g.score_target)
    row=W.QHBoxLayout();g.score_fans=[]
    def strike(h,z):answer(g,h,z)
    keyboard_hint=W.QLabel('电脑教学：主键盘1～7＝左手DO～SI，小键盘1～7＝右手DO～SI（开启Num Lock）。数字直接作答，无需鼠标选区；也可点击下方扇区。七音曲目支持数字键，C档按目标自动设置，不用W/S。正确绿闪结束后再按下一音。')
    keyboard_hint.setWordWrap(True);col.addWidget(keyboard_hint)
    for h,name in enumerate(('左手','右手')):
        box=W.QGroupBox(name+('：主键盘1～7／鼠标' if h==0 else '：小键盘1～7／鼠标'));box.setProperty('hand','left' if h==0 else 'right');layout=W.QVBoxLayout(box);fan=MouseFan(h);fan.hdmi_theme=True;fan.setMinimumHeight(150);fan.struck.connect(lambda z,hand=h:g.safe(lambda:strike(hand,z)));layout.addWidget(fan);row.addWidget(box);g.score_fans.append(fan)
    col.addLayout(row)
    col.addStretch()

def set_score(g,score):
    from lab_score_import import ensure_idle
    ensure_idle(g)
    if g.score_worker:g.score_worker.cancel()
    g.score_converting=False;g.score_convert_button.setText('格式转换');invalidate(g,True)
    g.score_input=load_score(score);g.score_summary.setText('已载入曲谱，请点击“检查转换格式”')

def preview(g):
    g.score_preview=None
    if g.score_input is None:return
    layout='auto' if g.score_layout.currentIndex()==0 else g.score_layout.currentIndex()-1
    out=compile_score(g.score_input,layout);g.score_preview=out;g.score_confirm.setChecked(False)
    g.score_summary.setText(f"{out['score']['title']} · {out['count']}步 · 布局{[7,5,12][out['profile']]}音区 · CRC32 {out['crc32']:08X}；教学自动目标C档，时值只控制发声保持，不按节拍评分。")
    g.score_table.setRowCount(len(out['rows']))
    from lab_score import note_name
    for i,r in enumerate(out['rows']):
        values=[i+1,'右' if r['hand']=='right' else '左',note_name(r['original_midi']),r['note'],r['zone']+1,r['midi']//12-1,r['hold_ms'],r['rest_before_ticks']]
        for k,v in enumerate(values):g.score_table.setItem(i,k,W.QTableWidgetItem(str(v)))
    g.score_changes.setPlainText('\n'.join(out['changes']+out['warnings']) or '无需音域／时值适配。自然衰减可能早于松键变轻。')

def upload(g):
    if g.score_converting:raise ValueError('请先完成转换和检查')
    if upload_active(g):raise ValueError('曲谱正在上传，请勿重复点击')
    if not g.score_preview:raise ValueError('请先检查转换格式')
    if not g.engine.ready or not g.engine.capabilities.get('score_v1'):raise ValueError('需要连接支持曲谱的GEST27固件，或运行曲谱模拟')
    if g.score_preview['requires_confirmation'] and not g.score_confirm.isChecked():raise ValueError('请先确认适配内容')
    g.stop_live('曲谱上传已停止自动采样');g.duo_sync.setChecked(False)
    p=dict(score=g.score_input,layout='auto' if g.score_layout.currentIndex()==0 else g.score_layout.currentIndex()-1,confirmed=g.score_confirm.isChecked())
    g.score_job=g.submit_command('score.upload',p)['id']

def refresh(g):
    if not hasattr(g,'score_status'):return
    e=g.engine;s=e.score_state;ready=e.ready and e.capabilities.get('score_v1',False)
    g.score_upload_button.setEnabled(ready and g.score_preview is not None and not g.score_converting and (not g.score_job or g.controller.job(g.score_job)['state'] in ('completed','failed','cancelled')))
    if g.score_job:
        j=g.controller.job(g.score_job);g.score_status.setText(j['message']);g.score_progress.setValue(round(100*j.get('progress',0)))
        if j['state']=='completed':g.score_progress.setValue(100)
    elif not ready:g.score_status.setText('请连接设备，或在高级选项中体验模拟教学。')
    else:g.score_status.setText(f"板内曲目：{'已校验' if s.get('loaded') else '未上传'}；{s.get('total',0)}步，CRC {s.get('crc32',0):08X}；断电丢失。")
    if s.get('selected'):
        g.score_target.setText(f"目标 {'右' if s.get('hand') else '左'}手 · 音区{s.get('zone',0)+1} · MIDI {s.get('note',60)} · C{[4,5,2,3][s.get('octave',0)]} · {min(s.get('position',0)+1,s.get('total',0))}/{s.get('total',0)} · 正确{s.get('correct',0)} / 错击{s.get('wrong',0)} · {'已完成' if s.get('finished') else '自动按目标设档'}")
    for h,fan in enumerate(g.score_fans):
        profile=s.get('profile',0)
        if fan.profile!=profile:fan.profile=profile;fan.hover=None
        fan.lesson_target=s.get('zone') if s.get('selected') and not s.get('finished') and s.get('hand')==h else None
        fan.lesson_feedback=e.instrument_state.get('feedback',0) if e.instrument_state.get('feedback_hand')==h else 0
        fan.lesson_feedback_zone=e.instrument_state.get('feedback_zone');fan.update()


def answer(g,h,z):
    e=g.engine;s=e.score_state;state=e.instrument_state
    if not e.ready or state.get('mode')!=2 or state.get('lesson_source')!=1 or not e.duo.get('running') or not s.get('loaded') or not s.get('selected') or s.get('finished'):
        e.status='请先上传曲目、选择电脑教学来源并开始';return
    if s.get('profile',0)!=0:
        e.status='数字教学请使用七音布局';return
    if s.get('feedback')==1 or state.get('feedback')==1:
        e.status='正确反馈中，请等待下一目标';return
    if g.score_answer_job and g.controller.job(g.score_answer_job)['state'] not in ('completed','failed','cancelled'):
        e.status='正在等待板上判题，请勿连按';return
    g.score_fans[h].hover=z;g.score_fans[h].update()
    job=g.safe(lambda:g.submit_command('lesson.key',dict(hand=h,zone=z,position=s.get('position',0),crc32=s.get('crc32',0))))
    if job:g.score_answer_job=job['id']
