"""Focused GUI/model regression; all device data here is explicitly simulated."""
import os,sys,time,math,json,tempfile
from pathlib import Path
os.environ['QT_QPA_PLATFORM']='offscreen'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from tanglab import Window,W,C
from PySide6.QtTest import QTest
from lab_duo import note_map,PROFILES,CHANNELS,config_payload

app=W.QApplication([]);w=Window()
def wait(p,seconds=6):
    end=time.monotonic()+seconds
    while not p():
        QTest.qWait(15)
        if time.monotonic()>end:raise AssertionError('timed out')
def command(a,p=None):
    j=w.submit_command(a,p or {});wait(lambda:w.controller.job(j['id'])['state'] in ('completed','failed','cancelled'))
    r=w.controller.job(j['id']);assert r['state']=='completed',r
    return r['result']
try:
    for profile,offsets in enumerate(PROFILES):
        fan=w.duo_fans[0];fan.resize(400,230);fan.profile=profile;cx,cy,r=fan.geometry_values()
        for z,offset in enumerate(offsets):
            a=math.radians(-90+(z+.5)*180/len(offsets))
            assert fan.zone_at(cx+.7*r*math.sin(a),cy-.7*r*math.cos(a))==z
            assert note_map(profile,z)==[60+offset]
        assert fan.zone_at(cx,cy) is None and fan.zone_at(cx,cy+1) is None
    assert note_map(0,1,chord=True)==[62,65,69]
    try:config_payload({'gain':65});raise AssertionError('unsafe gain accepted')
    except ValueError:pass
    command('duo.demo');w.refresh_duo();assert not w.engine.duo['running']
    command('duo.configure',dict(run=True));w.refresh_duo()
    assert w.duo_volume.maximum()==256 and w.duo_holds[0].isEnabled()
    command('duo.configure',dict(run=True,gain=256,hold_ms=[1500,2000],release_ids=[1,2]))
    assert w.engine.duo_config['gain']==256 and w.engine.duo_config['hold_ms']==[1500,2000]
    command('duo.configure',dict(run=True,gain=32))
    assert w.engine.capabilities['duo_quality'] and w.duo_presets[0].count()==6
    cfg,wire=config_payload(dict(presets=[4,5],gain=128,piano_hold=[True,False],piano_decay_s=[6.,.2]),True,True)
    assert len(wire)==20 and wire[15]==1
    command('duo.configure',dict(presets=[4,5],gain=32,piano_hold=[True,False],piano_decay_s=[6.,.2]))
    command('duo.strike',dict(hand=0,zone=0,capture=True));assert w.engine.duo_config['presets']==[4,5]
    command('duo.demo');command('duo.configure',dict(run=True,gain=32))
    assert w.engine.channel_names==CHANNELS and not w.table.isEnabled()
    for i in range(10):
        result=command('duo.strike',dict(hand=i%2,zone=i%7,capture=True))
        assert w.engine.audio.shape==(512,5) and w.engine.audio_metadata['event_id']==result['event_id']
    assert w.engine.duo['hits']==[5,5]
    w.refresh_duo();before=w.duo_scope_lines[0].yData.copy()
    w.pause.setChecked(True);command('capture',{'points':2048});w.refresh_duo()
    assert np.array_equal(before,w.duo_scope_lines[0].yData)
    w.pause.setChecked(False);w.refresh_duo();assert len(w.duo_scope_lines[0].yData)==2048
    assert w.engine.audio_metadata['event_id']==0
    with tempfile.TemporaryDirectory() as folder:
        out=Path(folder);w.write_audio(out/'采样.csv');w.write_history(out/'历史.csv')
        assert '干声左' in (out/'采样.csv').read_text(encoding='utf-8-sig').splitlines()[0]
        assert json.loads((out/'采样.csv.json').read_text(encoding='utf-8'))['channels']==CHANNELS
    fan=w.duo_fans[0];fan.profile=0;hits=[];fan.struck.connect(hits.append)
    pos=C.QPoint(int(fan.width()/2),int(fan.height()/2))
    QTest.mouseClick(fan,C.Qt.MouseButton.LeftButton,pos=pos)
    QTest.mouseDClick(fan,C.Qt.MouseButton.LeftButton,pos=pos)
    assert len(hits)==2,hits
    command('duo.stop');assert not w.engine.duo['running']
    command('demo');w.refresh_duo();assert w.table.isEnabled() and w.engine.channel_names[0]=='声部一'
    print('PASS simulated DUO: fan geometry/mapping, gain bounds, ten strikes, 512/2048, pause, CSV metadata, click/doubleclick, stop, legacy compatibility')
finally:w.close()
