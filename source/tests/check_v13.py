"""1.3 controls, ACK ordering, compatibility, exact captures and recording replay."""
import os,sys,time,struct,tempfile
os.environ['QT_QPA_PLATFORM']='offscreen'
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from tanglab import Window,W
from PySide6.QtTest import QTest
import lab_protocol as P

app=W.QApplication([]);w=Window();w.show();e=w.engine;c=w.controller
def done(action,params=None):
    j=c.submit(action,params);end=time.monotonic()+5
    while c.job(j['id'])['state'] not in ('completed','failed'):
        QTest.qWait(10)
        assert time.monotonic()<end
    return c.job(j['id'])
try:
    done('demo');w.refresh();w.service_live()
    assert w.capture_size.currentIndex()==0
    for seconds in (.2,6,30):
        ch,hold,coeff=struct.unpack('<BBH',P.piano_payload(3,True,seconds))
        assert (ch,hold)==(3,1)
        predicted=(1-coeff/2**24)**(seconds*48000)
        assert .097<predicted<.103,(seconds,coeff,predicted)
    # Set all four through the existing Apply entry and persist independent values.
    for i in range(4):
        w.piano_channel.setCurrentIndex(i)
        w.piano_hold.setChecked(i%2==0);w.piano_decay.setValue(i+1)
    w.piano_channel.setCurrentIndex(0)
    assert w.piano_hold.isChecked() and w.piano_decay.value()==1
    for i,controls in enumerate(w.controls):
        controls=dict(controls);controls['wave'].setCurrentIndex(4)
        controls['gate'].setChecked(i==0);controls['sustain'].setValue(.7)
    w.apply_voices()
    end=time.monotonic()+5
    while c.job(w.last_agent_job)['state'] not in ('completed','failed'):
        QTest.qWait(10);assert time.monotonic()<end
    assert c.job(w.last_agent_job)['state']=='completed'
    assert [v['piano_decay_s'] for v in e.piano_settings]==[1,2,3,4]
    assert [v['piano_hold'] for v in e.piano_settings]==[True,False,True,False]
    for points in (512,2048):
        j=done('capture',dict(points=points));assert j['state']=='completed',j
        assert e.audio.shape==(points,5)
        s=c.spectrum_info(0);assert len(s['frequency_hz'])==points//2+1
        assert s['frequency_hz'][1]==48000/points
    with tempfile.TemporaryDirectory(dir='D:/codex/temp/tanglab-v13-20261008') as folder:
        folder=Path(folder);e.start_record(folder/'recording')
        done('capture',dict(points=512));e.stop_record()
        (folder/'export').mkdir();c.export_to(folder/'export')
        assert len((folder/'export/采样.csv').read_text(encoding='utf-8-sig').splitlines())==513
        result=done('replay',dict(path=str(folder/'recording')));assert result['state']=='completed',result
        assert e.audio.shape==(512,5)
    # Old firmware explicitly rejects new settings before sending any command.
    e.source='测试串口（非硬件）';e.ready=True;e.capabilities['piano_control']=False
    calls=[]
    def failed_send(kind,payload=b''):
        calls.append(kind);e.command_results[123]=dict(state='failed',error='测试配置拒绝');return 123
    e.send=failed_send
    j=done('voices.set',dict(voices=[dict(channel=0,piano_hold=True)]))
    assert j['state']=='failed' and '1.3' in j['message'] and not calls
    e.capabilities['piano_control']=True
    j=done('voices.set',dict(voices=[dict(channel=0,piano_hold=True)]))
    assert j['state']=='failed' and calls==[P.PIANO_CONFIG],'VOICE sent before successful piano ACK'
    e.capabilities['capture_sizes']=[2048];w.service_live()
    assert w.capture_size.currentIndex()==1 and not w.capture_size.model().item(0).isEnabled()
    print('PASS v1.3 per-voice controls, T10 coefficients, ACK order, old firmware guard, 512/2048 FFT, CSV and recording replay')
finally:w.close()
