"""Six-button score import controls, shared by conversion and external JSON."""
import json,re,sys
from pathlib import Path
from PySide6 import QtCore as C, QtGui as G, QtWidgets as W
from lab_score import ASSETS,load_score,compile_score
from lab_score_ai import ScoreDocument,parse_pages,ConversionWorker

def data_dir():
    return Path(C.QStandardPaths.writableLocation(C.QStandardPaths.StandardLocation.AppLocalDataLocation))/'曲谱'

class DropPreview(W.QLabel):
    chosen=C.Signal(str)
    def __init__(self):
        super().__init__('将一份谱子图片或PDF拖到这里，或点击“选择文件”'); self.setAcceptDrops(True)
        self.setAlignment(C.Qt.AlignmentFlag.AlignCenter); self.setMinimumHeight(150); self.setMaximumHeight(240)
        self.setObjectName('scoreDrop')
    def dragEnterEvent(self,event):
        if event.mimeData().hasUrls(): event.acceptProposedAction()
    def dropEvent(self,event):
        urls=event.mimeData().urls()
        if len(urls)!=1 or not urls[0].isLocalFile():
            W.QMessageBox.warning(self,'选择文件','每次请拖入一个本地文件'); return
        self.chosen.emit(urls[0].toLocalFile()); event.acceptProposedAction()

def invalidate(g,clear_input=False):
    g.score_generation+=1; g.score_preview=None; g.score_confirm.setChecked(False)
    g.score_table.setRowCount(0); g.score_changes.clear(); g.score_upload_button.setEnabled(False)
    if clear_input: g.score_input=None
    g.score_summary.setText('尚未检查当前曲谱，不能上传')

def upload_active(g):
    return bool(g.score_job and g.controller.job(g.score_job)['state'] not in ('completed','failed','cancelled'))

def ensure_idle(g):
    if upload_active(g): raise ValueError('正在上传，请先等待完成或取消上传，再更换曲谱')

def show_page(g):
    if g.score_document:
        image=g.score_document.render(g.score_page.currentIndex(),700)
        g.score_file_preview.setPixmap(G.QPixmap.fromImage(image).scaled(600,210,C.Qt.AspectRatioMode.KeepAspectRatio,C.Qt.TransformationMode.SmoothTransformation))

def source_changed(g,path):
    ensure_idle(g)
    if g.score_worker: g.score_worker.cancel()
    g.score_converting=False; g.score_convert_button.setText('格式转换')
    invalidate(g,True); g.score_path=None
    g.score_file_preview.clear();g.score_file_notice.setText('正在打开文件；尚未发送到AI')
    if g.score_document and g.score_document.pdf:g.score_document.pdf.close()
    g.score_document=None; g.score_page.blockSignals(True);g.score_page.clear();g.score_page.blockSignals(False)
    doc=ScoreDocument(path);g.score_document=doc;g.score_path=str(doc.path)
    g.score_pages.setText(''); g.score_page.addItems([f'第{i+1}页' for i in range(doc.count)])
    show_page(g); update_notice(g)

def update_notice(g):
    if not g.score_document:return
    try:
        pages=parse_pages(g.score_pages.text(),g.score_document.count)
        g.score_file_notice.setText(f'文件：{g.score_document.path.name} · 共{g.score_document.count}页 · 将发送{len(pages)}页给配置的AI。点击“格式转换”即授权本次发送。')
    except ValueError as exc:g.score_file_notice.setText(str(exc))

def select_file(g):
    path,_=W.QFileDialog.getOpenFileName(g,'选择谱子图片或PDF','','谱子 (*.png *.jpg *.jpeg *.webp *.pdf)')
    if path:source_changed(g,path)

def import_json(g):
    ensure_idle(g)
    path,_=W.QFileDialog.getOpenFileName(g,'导入其他AI转换后的文件','','TangLab曲谱 (*.tangscore.json *.json)')
    if path:
        if g.score_worker:g.score_worker.cancel()
        g.score_converting=False;g.score_convert_button.setText('格式转换');invalidate(g,True)
        g.score_input=load_score(path);g.score_summary.setText('已导入：'+path+'；请点击“检查转换格式”')

def convert_clicked(g):
    if g.score_converting:
        g.score_worker.cancel();g.score_converting=False;g.score_generation+=1
        g.score_convert_button.setText('格式转换');g.score_summary.setText('已取消；在途网络请求可能等待超时，结果不会应用');return
    ensure_idle(g)
    if g.score_worker and g.score_worker.thread.is_alive():raise ValueError('上次取消的请求尚未退出，请稍候（最长约90秒）')
    if not g.score_path:raise ValueError('请先选择图片或PDF文件')
    if not all(x.text().strip() for x in (g.score_ai_url,g.score_ai_model,g.score_ai_key)):
        g.score_ai_group.setChecked(True);raise ValueError('请展开AI设置，填写服务地址、视觉模型名和密钥')
    from lab_score_ai import endpoint
    endpoint(g.score_ai_url.text())
    pages=parse_pages(g.score_pages.text(),g.score_document.count)
    invalidate(g,True);g.score_converting=True;g.score_convert_button.setText('取消转换')
    revision=g.score_generation;worker=ConversionWorker(g);g.score_worker=worker
    worker.progress.connect(lambda a,b,t:g.score_summary.setText(t) if g.score_converting and revision==g.score_generation else None)
    worker.completed.connect(lambda rev,value,error:converted(g,rev,value,error))
    worker.start(revision,g.score_path,pages,g.score_ai_url.text(),g.score_ai_model.text(),g.score_ai_key.text())

def converted(g,revision,value,error):
    if revision!=g.score_generation or not g.score_converting:return
    g.score_converting=False;g.score_convert_button.setText('格式转换')
    if error:g.score_summary.setText('转换失败：'+error);return
    g.score_input=value;g.score_summary.setText(f'转换完成：{value["title"]} · {len(value["steps"])}步；请对照原谱并点击“检查转换格式”')
    g.score_changes.setPlainText('\n'.join(value.get('warnings',[])))

def checked(g):
    ensure_idle(g)
    if g.score_converting:raise ValueError('请先完成转换')
    if g.score_input is None:raise ValueError('请先转换谱子或导入转换后的JSON文件')
    from lab_score_ui import preview
    preview(g)
    folder=data_dir()/'曲库';folder.mkdir(parents=True,exist_ok=True)
    title=re.sub(r'[<>:"/\\|?*\x00-\x1f]','_',g.score_input['title']).rstrip(' .')[:60] or '曲谱'
    # Prefix avoids Windows reserved filenames such as CON and AUX.
    path=folder/('曲谱-'+title+'.tangscore.json');n=2
    while path.exists():path=folder/(f'曲谱-{title}-{n}.tangscore.json');n+=1
    try:path.write_text(json.dumps(g.score_input,ensure_ascii=False,indent=2),encoding='utf-8')
    except OSError:
        invalidate(g);raise ValueError('曲库保存失败，请检查磁盘空间和用户目录权限') from None
    g.score_summary.setText(g.score_summary.text()+'\n已保存标准曲谱：'+str(path)+'；请人工核对识谱内容。')

def copy_rules():W.QApplication.clipboard().setText((ASSETS/'给AI的转换提示词.txt').read_text(encoding='utf-8'))

def save_settings(g):
    folder=data_dir();folder.mkdir(parents=True,exist_ok=True)
    from lab_score_ai import endpoint
    url=g.score_ai_url.text().strip()
    if url:endpoint(url)
    (folder/'ai-settings.json').write_text(json.dumps({'url':url,'model':g.score_ai_model.text().strip()},ensure_ascii=False),encoding='utf-8')
    from lab_secret import save_key
    save_key(folder,g.score_ai_key.text().strip() if g.score_remember_key.isChecked() else '')
    g.score_settings_note.setText('设置已保存；密钥由Windows加密，下次自动读取' if g.score_remember_key.isChecked() else '地址和模型已保存；本机保存的密钥已清除')

def build_import(g,col):
    g.score_generation=0;g.score_worker=None;g.score_document=None;g.score_path=None;g.score_converting=False
    row=W.QHBoxLayout()
    def b(text,fn):
        button=W.QPushButton(text);button.clicked.connect(lambda:g.safe(fn));row.addWidget(button);return button
    b('选择文件',lambda:select_file(g));g.score_convert_button=b('格式转换',lambda:convert_clicked(g))
    b('检查转换格式',lambda:checked(g))
    g.score_upload_button=b('上传',lambda:__import__('lab_score_ui').upload(g));g.score_upload_button.setEnabled(False)
    b('复制转换规则',copy_rules);b('导入转换后的文件',lambda:import_json(g));col.addLayout(row)
    g.score_file_notice=W.QLabel('选择图片/PDF后配置AI即可转换；也可复制规则交给外部AI，再导入JSON。');g.score_file_notice.setWordWrap(True);col.addWidget(g.score_file_notice)
    row=W.QHBoxLayout();g.score_file_preview=DropPreview();row.addWidget(g.score_file_preview,1)
    opts=W.QFormLayout();g.score_pages=W.QLineEdit();g.score_pages.setPlaceholderText('全部；或1-3,5');g.score_pages.setToolTip('按页码升序转换；多页需自行复核跨页连音、反复及调号')
    g.score_page=W.QComboBox();opts.addRow('转换页码',g.score_pages);opts.addRow('预览页',g.score_page);row.addLayout(opts);col.addLayout(row)
    g.score_file_preview.chosen.connect(lambda path:g.safe(lambda:source_changed(g,path)))
    g.score_page.currentIndexChanged.connect(lambda:g.safe(lambda:show_page(g)))
    def pages_changed():
        if g.score_worker:g.score_worker.cancel()
        g.score_converting=False;g.score_convert_button.setText('格式转换');invalidate(g,True);update_notice(g)
    g.score_pages.textEdited.connect(pages_changed)
    ai=W.QGroupBox('AI设置（OpenAI兼容视觉接口）');ai.setCheckable(True);ai.setChecked(False);lay=W.QVBoxLayout(ai);fields=W.QWidget();form=W.QFormLayout(fields);lay.addWidget(fields);fields.setVisible(False);ai.toggled.connect(fields.setVisible);g.score_ai_group=ai
    g.score_ai_url=W.QLineEdit();g.score_ai_url.setPlaceholderText('https://服务地址/v1')
    g.score_ai_model=W.QLineEdit();g.score_ai_model.setPlaceholderText('支持图片输入的模型名称')
    g.score_ai_key=W.QLineEdit();g.score_ai_key.setEchoMode(W.QLineEdit.EchoMode.Password);g.score_ai_key.setPlaceholderText('可勾选在本机记住密钥')
    for text,field in [('服务地址',g.score_ai_url),('模型名',g.score_ai_model),('密钥',g.score_ai_key)]:form.addRow(text,field)
    g.score_remember_key=W.QCheckBox('在本机记住密钥（Windows加密，仅当前用户可读取）');form.addRow(g.score_remember_key)
    save=W.QPushButton('保存AI设置');save.clicked.connect(lambda:g.safe(lambda:save_settings(g)));form.addRow(save)
    g.score_settings_note=W.QLabel('仅支持Chat Completions图片接口；尚未配置时可用外部AI转换。');g.score_settings_note.setWordWrap(True);form.addRow(g.score_settings_note);col.addWidget(ai)
    try:
        settings=json.loads((data_dir()/'ai-settings.json').read_text(encoding='utf-8'));g.score_ai_url.setText(settings.get('url',''));g.score_ai_model.setText(settings.get('model',''))
    except (OSError,ValueError):pass
    try:
        from lab_secret import load_key
        saved=load_key(data_dir())
        if saved:g.score_ai_key.setText(saved);g.score_remember_key.setChecked(True);g.score_settings_note.setText('已读取本机加密密钥')
    except (OSError,ValueError):g.score_settings_note.setText('本机加密密钥无法读取，请重新填写并保存')
    C.QCoreApplication.instance().aboutToQuit.connect(lambda:g.score_worker.cancel() if g.score_worker else None)
