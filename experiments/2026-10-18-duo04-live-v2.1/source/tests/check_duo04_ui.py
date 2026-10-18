import os,sys,time,struct
from pathlib import Path
os.environ['QT_QPA_PLATFORM']='offscreen'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tanglab import Window,W
from PySide6.QtTest import QTest
from lab_instrument import PRESETS,validate
app=W.QApplication([])
from lab_ui import chinese_qt
chinese_qt(app)
w=Window();w.show()
def command(name,params=None):
    job=w.submit_command(name,params or {});until=time.monotonic()+8
    while w.controller.job(job['id'])['state'] not in ('completed','failed','cancelled'):
        QTest.qWait(10)
        assert time.monotonic()<until,'GUI command timeout'
    j=w.controller.job(job['id']);assert j['state']=='completed',j;return j
try:
    command('instrument.demo');w.refresh_duo()
    assert w.instrument_group.isEnabled()
    assert [w.duo_presets[0].itemText(i) for i in range(4)]==PRESETS
    command('instrument.set',{'mode':0,'left_timbre':1,'left_hold_ms':1000,'run':True})
    assert w.engine.instrument_state['mode']==0 and w.engine.duo_config['run']
    w.check_external_focus();QTest.qWait(50)
    assert w.engine.duo_config['run'],'autonomous mode stopped on GUI focus'
    command('instrument.set',{'lesson':2,'lesson_start':True})
    assert w.engine.instrument_state['mode']==2
    command('duo.configure',dict(run=True,presets=[0,3],hold_ms=[1000,1000]))
    assert w.engine.instrument_state['mode']==1
    command('duo.strike',dict(hand=0,zone=0,profile=0,velocity=48,capture=True))
    command('capture',dict(points=512));assert w.engine.audio.shape==(512,5)
    w.refresh_duo();w.tabs.setCurrentIndex(w.duo_page_index);QTest.qWait(100)
    if len(sys.argv)>1:w.grab().save(sys.argv[1])
    command('duo.stop');command('duo.demo');w.refresh_duo()
    assert not w.instrument_group.isEnabled() and w.duo_presets[0].count()==6
    try:validate({'left_hold_ms':99});raise AssertionError('range accepted')
    except ValueError:pass
    print('PASS DUO04/legacy capabilities, four timbres, autonomous focus, mode/readback, teaching controls, capture, range rejection; SIMULATED')
finally:w.close();app.processEvents()
