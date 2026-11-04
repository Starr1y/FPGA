"""Local mock only: never calls a paid model or serial hardware."""
import os,sys,json,threading,time,tempfile,unittest
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6 import QtCore as C,QtGui as G,QtWidgets as W
from lab_score_ai import ScoreDocument,convert,parse_output,parse_pages,endpoint,Cancelled

SCORE={'format':'tanglab.score','version':1,'title':'模拟测试','tempo_bpm':90,'ticks_per_quarter':480,'steps':[{'hand':'right','midi':60,'duration_ticks':480}]}

class Handler(BaseHTTPRequestHandler):
    mode='ok';requests=[]
    def log_message(self,*args):pass
    def do_POST(self):
        content=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        type(self).requests.append(content)
        mode=type(self).mode
        if mode=='slow':time.sleep(.2)
        if mode=='401':self.send_response(401);self.end_headers();return
        text=json.dumps(SCORE,ensure_ascii=False)
        if mode=='invalid':text='不是JSON'
        if mode=='long':text=json.dumps(dict(SCORE,steps=SCORE['steps']*2049))
        result=json.dumps({'choices':[{'message':{'content':text}}]}).encode()
        self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers()
        try:self.wfile.write(result)
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass

class Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app=W.QApplication.instance() or W.QApplication([])
        cls.app.setApplicationName('TangLab271Tests');C.QStandardPaths.setTestModeEnabled(True)
        cls.tmp=tempfile.TemporaryDirectory(prefix='曲谱转换-',dir=os.environ.get('TANGLAB_TEST_WORK') or None);cls.folder=Path(cls.tmp.name)
        cls.png=cls.folder/'中文谱子.png';im=G.QImage(300,200,G.QImage.Format.Format_RGB32);im.fill(C.Qt.GlobalColor.white);assert im.save(str(cls.png))
        cls.pdf=cls.folder/'双页谱子.pdf';writer=G.QPdfWriter(str(cls.pdf));painter=G.QPainter(writer);painter.drawText(100,200,'Page 1');writer.newPage();painter.drawText(100,200,'Page 2');painter.end();del writer
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=cls.server.serve_forever,daemon=True).start();cls.url=f'http://127.0.0.1:{cls.server.server_port}/v1'
    @classmethod
    def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();cls.tmp.cleanup()
    def setUp(self):Handler.mode='ok';Handler.requests=[]
    def run_convert(self,path=None,pages=None,**kw):return convert(path or self.png,pages or [0],self.url,'mock-vision','mock-secret',kw.pop('event',threading.Event()),lambda *x:None,**kw)
    def test_image_request_and_fence(self):
        score=self.run_convert();self.assertEqual(score['steps'],SCORE['steps']);self.assertEqual(Handler.requests[0]['model'],'mock-vision')
        self.assertTrue(Handler.requests[0]['messages'][1]['content'][1]['image_url']['url'].startswith('data:image/png;base64,'))
        self.assertEqual(parse_output('```json\n'+json.dumps(SCORE)+'\n```'),SCORE)
        with self.assertRaises(ValueError):parse_output('说明文字'+json.dumps(SCORE))
    def test_pdf_pages_and_merge(self):
        doc=ScoreDocument(self.pdf);self.assertEqual(doc.count,2);self.assertFalse(doc.render(1).isNull());doc.pdf.close()
        score=self.run_convert(self.pdf,[0,1]);self.assertEqual(len(score['steps']),2);self.assertEqual(len(Handler.requests),2)
        self.assertEqual(parse_pages('2,1-2',2),[0,1])
        with self.assertRaises(ValueError):parse_pages('3',2)
        with self.assertRaises(ValueError):parse_pages('2-1',2)
    def test_auth_invalid_long_timeout_cancel(self):
        for mode in ('401','invalid','long'):
            Handler.mode=mode
            with self.assertRaises(ValueError):self.run_convert()
        Handler.mode='slow'
        with self.assertRaisesRegex(ValueError,'超时'):self.run_convert(timeout=.03)
        event=threading.Event();event.set()
        with self.assertRaises(Cancelled):self.run_convert(event=event)
        event=threading.Event();threading.Timer(.03,event.set).start()
        with self.assertRaises(Cancelled):self.run_convert(event=event)
    def test_corrupt_file_endpoint(self):
        bad=self.folder/'坏.pdf';bad.write_bytes(b'broken')
        with self.assertRaises(ValueError):ScoreDocument(bad)
        self.assertEqual(endpoint('https://example.com'),'https://example.com/v1/chat/completions')
        self.assertEqual(endpoint(self.url+'/chat/completions'),self.url+'/chat/completions')
        with self.assertRaises(ValueError):endpoint('https://example.com?key=secret')
    def test_ui_check_invalidation_save_and_stale_result(self):
        from tanglab import Window
        import lab_score_ui as ui,lab_score_import as imp
        w=Window();w.timer.stop()
        try:
            ui.set_score(w,SCORE);self.assertIsNone(w.score_preview)
            imp.checked(w);self.assertEqual(w.score_table.rowCount(),1)
            self.assertTrue(list((imp.data_dir()/'曲库').glob('*.json')))
            w.score_layout.setCurrentIndex(3);self.assertIsNone(w.score_preview);self.assertFalse(w.score_upload_button.isEnabled())
            old=w.score_generation;w.score_converting=True;imp.invalidate(w,True);imp.converted(w,old,SCORE,'');self.assertIsNone(w.score_input)
            w.score_converting=False;imp.source_changed(w,str(self.png));self.assertEqual(w.score_document.count,1)
            w.score_ai_url.setText(self.url);w.score_ai_model.setText('mock');w.score_ai_key.setText('never-save-this')
            imp.save_settings(w);self.assertNotIn('never-save-this',(imp.data_dir()/'ai-settings.json').read_text())
            w.score_ai_key.clear();self.assertFalse(w.engine.capabilities.get('score_v1'));ui.refresh(w);self.assertFalse(w.score_upload_button.isEnabled())
        finally:w.close();self.app.processEvents()

if __name__=='__main__':unittest.main(verbosity=2)
