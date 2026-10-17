import os,sys,tempfile,csv,time
os.environ['QT_QPA_PLATFORM']='offscreen'
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from tanglab import Window,W
from PySide6.QtTest import QTest
app=W.QApplication([]);w=Window();w.show()
def wait(predicate,seconds=4):
    end=time.monotonic()+seconds
    while not predicate():
        QTest.qWait(20)
        if time.monotonic()>end:raise AssertionError('wait timeout')
try:
    w.demo();wait(lambda:w.engine.ready);w.refresh()
    w.toggle_live();wait(lambda:w.engine.audio_count>=3)
    # Commands share the same worker while automatic acquisition is running.
    job=w.submit_command('ping');wait(lambda:w.controller.job(job['id'])['state']=='completed')
    w.stop_live();wait(lambda:w.controller.active is None and w.controller.queue.empty());w.service_live()
    baseline=w.engine.audio_count;QTest.qWait(300);assert w.engine.audio_count==baseline
    for _ in range(34):w.engine.make_demo_audio()
    assert len(w.engine.audio_history)==30
    w.live_view.setCurrentIndex(1);w.refresh()
    assert np.isnan(w.curves[0].xData).sum()==30
    assert w.spectrum_data is not None and len(w.spectrum_data[0])==1025
    old=w.curves[0].yData.copy();phase=w.spectrum_data[2].copy()
    w.pause.setChecked(True);w.engine.make_demo_audio();w.refresh()
    assert np.array_equal(old,w.curves[0].yData,equal_nan=True)
    assert np.array_equal(phase,w.spectrum_data[2],equal_nan=True)
    w.pause.setChecked(False);w.refresh()
    w.plots[0].getViewBox().sigRangeChangedManually.emit([True,False]);assert not w.follow_latest.isChecked()
    w.follow_latest.setChecked(True);w.refresh()
    with tempfile.TemporaryDirectory() as folder:
        path=Path(folder)/'历史.csv';w.write_history(path)
        with path.open(encoding='utf-8-sig') as f:rows=list(csv.reader(f))
        assert len(rows)==30*2048+1 and len({r[0] for r in rows[1:]})==30
    original_capture=w.controller.capture
    def slow_capture(*args,**kwargs):
        time.sleep(.3);return original_capture(*args,**kwargs)
    w.controller.capture=slow_capture
    w.toggle_live();wait(lambda:w.controller.active is not None and w.controller.jobs[w.controller.active]['action']=='capture')
    w.clear_waveforms();wait(lambda:not w.clear_pending)
    assert not w.live_running and w.engine.audio is None and not w.engine.audio_history
    QTest.qWait(200);assert all(c.xData is None or not len(c.xData) for c in w.curves)
    w.toggle_live();wait(lambda:w.engine.audio_count>0);w.engine.ready=False;w.service_live();assert not w.live_running
    w.engine.ready=True
    # Force capture failure: loop must stop instead of retrying indefinitely.
    w.stop_live();wait(lambda:w.controller.active is None and w.controller.queue.empty())
    def fail(*args,**kwargs):raise TimeoutError('测试采集超时')
    w.controller.capture=fail;w.toggle_live();wait(lambda:not w.live_running)
    assert '超时' in w.live_message
    print('PASS live scheduling, command fairness, 30 segments, gaps, pause, spectrum, export, clear, disconnect, failure')
finally:w.close()
