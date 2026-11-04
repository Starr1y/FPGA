"""Opt-in local mock API/GUI check; never touches COM or external APIs."""
import json,threading,time,traceback
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from PySide6 import QtCore as C,QtGui as G,QtWidgets as W

def start(w,app,out):
    from lab_score_import import source_changed,convert_clicked,checked,import_json,invalidate
    from lab_score_ui import upload,refresh
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    # Opt-in mock-only diagnostic: contains no real API keys or provider data.
    import lab_score_ai
    original_convert=lab_score_ai.convert
    def trace_convert(*args,**kwargs):
        try:return original_convert(*args,**kwargs)
        except Exception:
            (out/'mock-conversion-trace.txt').write_text(traceback.format_exc(),encoding='utf-8');raise
    lab_score_ai.convert=trace_convert
    # Keep smoke-test library/configuration out of the real user's library.
    C.QStandardPaths.setTestModeEnabled(True)
    score=dict(format='tanglab.score',version=2,title='模拟识谱测试',tempo_bpm=90,steps=[dict(hand='right',midi=60,hold_ms=500)])
    class Handler(BaseHTTPRequestHandler):
        slow=False
        def log_message(self,*args):pass
        def do_POST(self):
            json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            time.sleep(.8 if type(self).slow else .12)
            raw=json.dumps({'choices':[{'message':{'content':'```json\n'+json.dumps(score,ensure_ascii=False)+'\n```'}}]}).encode()
            self.send_response(200);self.end_headers()
            try:self.wfile.write(raw)
            except OSError:pass
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
    image=G.QImage(800,300,G.QImage.Format.Format_RGB32);image.fill(C.Qt.GlobalColor.white);p=G.QPainter(image);p.setPen(C.Qt.GlobalColor.black)
    for y in (100,120,140,160,180):p.drawLine(40,y,750,y)
    p.drawEllipse(190,130,20,12);p.drawLine(210,135,210,70);p.end();img=out/'模拟谱面.png';image.save(str(img))
    pdf=out/'模拟双页.pdf';writer=G.QPdfWriter(str(pdf));p=G.QPainter(writer);p.drawImage(C.QRect(50,100,6000,2300),image);writer.newPage();p.drawImage(C.QRect(50,100,6000,2300),image);p.end();del writer
    external=out/'外部转换.tangscore.json';external.write_text(json.dumps(score,ensure_ascii=False),encoding='utf-8')
    w.score_ai_url.setText(f'http://127.0.0.1:{server.server_port}/v1');w.score_ai_model.setText('local-mock');w.score_ai_key.setText('mock-not-a-real-key')
    w.tabs.setCurrentIndex(w.tabs.count()-1);w.resize(1450,1000)
    state={'stage':0,'ticks':0,'job':None};deadline=time.monotonic()+45;checks=[]
    def submit(action,params):state['job']=w.submit_command(action,params)['id']
    def tick():
        try:
            state['ticks']+=1
            if time.monotonic()>deadline:raise TimeoutError('模拟转换联合检查超时')
            if state['job']:
                job=w.controller.job(state['job'])
                if job['state'] not in ('completed','failed','cancelled'):return
                assert job['state']=='completed',job['message'];state['job']=None
            n=state['stage']
            if n==0:source_changed(w,str(img));convert_clicked(w);state['stage']=1
            elif n==1:
                if w.score_converting:return
                assert w.score_input and w.score_preview is None,w.score_summary.text()
                checked(w);checks.append('图片AI转换、单层围栏、检查后曲库保存');submit('score.demo',{});state['stage']=2
            elif n==2:upload(w);state['job']=w.score_job;state['stage']=3
            elif n==3:
                assert w.engine.score_state.get('loaded');checks.append('转换结果模拟上传CRC及提交读回')
                source_changed(w,str(pdf));convert_clicked(w);state['stage']=4
            elif n==4:
                if w.score_converting:return
                assert len(w.score_input['steps'])==2,w.score_summary.text();checked(w);checks.append('双页PDF渲染与分批合并')
                Handler.slow=True;convert_clicked(w);state['stage']=5
            elif n==5:
                convert_clicked(w);assert not w.score_converting;state['wait']=time.monotonic()+1.2;state['stage']=6
            elif n==6:
                if time.monotonic()<state['wait']:return
                assert w.score_input is None and w.score_preview is None;checks.append('取消后旧结果不应用，GUI定时器持续运行')
                old=W.QFileDialog.getOpenFileName
                try:
                    W.QFileDialog.getOpenFileName=lambda *a,**k:(str(external),'');import_json(w)
                finally:W.QFileDialog.getOpenFileName=old
                assert w.score_preview is None;checked(w);upload(w);state['job']=w.score_job;state['stage']=7
            elif n==7:
                assert w.engine.score_state.get('total')==1;checks.append('外部JSON导入、检查、模拟上传')
                w.score_layout.setCurrentIndex(3);assert w.score_preview is None;checked(w)
                w.engine.capabilities['score_v1']=False;refresh(w);assert not w.score_upload_button.isEnabled();checks.append('布局变更失效、旧固件禁用上传')
                w.score_ai_key.clear();w.score_ai_url.clear();w.score_ai_model.clear();w.score_summary.setText('本地模拟接口验证完成；非真实模型、非板卡实测。')
                app.processEvents();w.grab().save(str(out/'新版曲谱页.png'))
                (out/'result.json').write_text(json.dumps({'result':'PASS','basis':'本地模拟API及模拟板卡，非实测','checks':checks,'responsive_timer_ticks':state['ticks']},ensure_ascii=False,indent=2),encoding='utf-8')
                w.conversion_test_timer.stop();server.shutdown();server.server_close();w.close()
        except Exception as exc:
            (out/'result.json').write_text(json.dumps({'result':'FAIL','error':str(exc),'traceback':traceback.format_exc()},ensure_ascii=False,indent=2),encoding='utf-8')
            w.conversion_test_timer.stop();server.shutdown();server.server_close();w.close();app.exit(1)
    w.conversion_test_timer=C.QTimer(w);w.conversion_test_timer.timeout.connect(tick);w.conversion_test_timer.start(40)
