import os,sys
os.environ['QT_QPA_PLATFORM']='offscreen'
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from tanglab import Window,W,C
from lab_ui import spectrum,chinese_qt
from PySide6.QtTest import QTest
app=W.QApplication([]);chinese_qt(app);w=Window();w.show();job=w.submit_command('demo')
for _ in range(100):
 if w.controller.job(job['id'])['state']=='completed':break
 QTest.qWait(20)
app.processEvents();w.refresh()
assert all(not line.isVisible() for group in w.cursor_lines for line in group)
for i in range(5):
 w.cursor_channel.setCurrentIndex(i);w.time_cursor.setChecked(True);w.amp_cursor.setChecked(True)
 assert all(line.isVisible() for line in w.cursor_lines[i])
 w.cursor_lines[i][0].setValue(2);w.cursor_lines[i][1].setValue(12)
 assert '100.00 Hz' in w.cursors.text()
w.focus_wave(3);app.processEvents();v=w.plots[3].getViewBox();line=w.cursor_lines[3][0]
start=w.graphics.mapFromScene(v.mapViewToScene(C.QPointF(line.value(),0)))
end=start+C.QPoint(35,0)
QTest.mousePress(w.graphics.viewport(),C.Qt.MouseButton.LeftButton,pos=start)
QTest.mouseMove(w.graphics.viewport(),end,delay=30)
QTest.mouseRelease(w.graphics.viewport(),C.Qt.MouseButton.LeftButton,pos=end)
app.processEvents();assert w.focused==3
w.focus_wave(None);w.stacked.setChecked(False);app.processEvents()
assert sum(line.isVisible() for group in w.cursor_lines for line in group)==4
w.stacked.setChecked(True);app.processEvents();assert all(s['time'] and s['amplitude'] for s in w.cursor_state)
menu=w.plots[0].getViewBox().make_menu();assert '导出图片…' in [a.text() for a in menu.actions()]
t=np.arange(2048)/48000;f,db,p=spectrum(np.cos(2*np.pi*750*t+np.pi/6)*16384,48000);k=np.argmax(db)
assert f[k]==750 and abs(db[k]+6.0206)<.01 and abs(p[k]-30)<.01
assert np.all(np.isnan(spectrum(np.zeros(2048),48000)[2]))
w.engine.audio=None;w.update_spectrum();assert w.spectrum_data is None and '包络' in w.spectrum_note.text()
w.engine.make_demo_audio();w.refresh();w.tabs.setCurrentIndex(5);app.processEvents();None
w.clear_waveforms();app.processEvents()
assert w.engine.audio is None and not w.engine.envelope and w.engine.capture_parts=={}
assert all(line.xData is None or len(line.xData)==0 for line in w.curves)
assert (w.fftline.xData is None or len(w.fftline.xData)==0) and w.spectrum_data is None and '已清空' in w.audio_note.text()
w.tabs.setCurrentIndex(0);w.focus_wave(2);app.processEvents();None
w.close();print('PASS: five-channel cursors, drag, layouts, Chinese menu, amplitude/phase, zero/preview, clear waveforms')
