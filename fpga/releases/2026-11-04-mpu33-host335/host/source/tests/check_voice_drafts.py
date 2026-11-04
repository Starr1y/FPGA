"""Regress delayed command completions overwriting a new note-on checkbox."""
import os,sys,time
from pathlib import Path
os.environ['QT_QPA_PLATFORM']='offscreen'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tanglab import Window,W
from PySide6.QtTest import QTest

app=W.QApplication([]);w=Window();w.agent_timer.stop();w.timer.stop();c=w.controller
def finished(key):
    end=time.monotonic()+5
    while c.job(key)['state'] not in ('completed','failed','cancelled'):
        QTest.qWait(10);assert time.monotonic()<end
    return c.job(key)
try:
    finished(c.submit('demo')['id']);w.refresh_agent()
    cells=dict(w.controls[0]);cells['wave'].setCurrentIndex(4);cells['gate'].setChecked(False)
    w.apply_voices();finished(w.last_agent_job)
    # Actual race: edit immediately after the worker completes but before UI polling.
    cells['gate'].setChecked(True);w.refresh_agent()
    assert cells['gate'].isChecked(),'Older Apply erased a new note-on'
    assert '尚未应用' in w.voice_apply_status.text()
    w.apply_voices();finished(w.last_agent_job);w.refresh_agent()
    assert w.engine.voices[0]['gate'] and cells['gate'].isChecked()
    # A second queued Apply must not be overwritten by the first job's completion.
    cells['gate'].setChecked(False);w.apply_voices();finished(w.last_agent_job)
    cells['gate'].setChecked(True);w.apply_voices();finished(w.last_agent_job)
    w.refresh_agent();assert cells['gate'].isChecked() and w.engine.voices[0]['gate']
    # Agent changes remain visible when there is no later local edit.
    finished(c.submit('voices.set',dict(voices=[dict(channel=0,gate=False)]))['id'])
    w.refresh_agent();assert not cells['gate'].isChecked()
    # But an Agent completion must also respect edits made while it was executing.
    finished(c.submit('voices.set',dict(voices=[dict(channel=0,gate=False)]))['id'])
    cells['gate'].setChecked(True);w.refresh_agent();assert cells['gate'].isChecked()
    # Failed jobs neither erase edits nor claim success.
    w.apply_voices();finished(w.last_agent_job);w.refresh_agent()
    w.engine.send=lambda *args:(_ for _ in ()).throw(ValueError('测试通信失败'))
    cells['gate'].setChecked(False);w.apply_voices();assert finished(w.last_agent_job)['state']=='failed'
    w.refresh_agent();assert not cells['gate'].isChecked() and '未完整应用' in w.voice_apply_status.text()
    print('PASS delayed Apply/Agent completion, queued release/note-on, draft preservation, failure feedback')
finally:w.close()
