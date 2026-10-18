"""No hardware: capture scheduling, wire reassembly, failure messages and repaint races."""
import os,sys,time,threading,struct
os.environ['QT_QPA_PLATFORM']='offscreen'
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from tanglab import Window,W
from PySide6.QtTest import QTest
import lab_protocol as P

app=W.QApplication([]);w=Window();w.show();e=w.engine;c=w.controller
def wait(predicate,seconds=3):
    end=time.monotonic()+seconds
    while not predicate():
        QTest.qWait(10)
        if time.monotonic()>end:raise AssertionError('timeout')
def done(job):
    wait(lambda:c.job(job['id'])['state'] in ('completed','failed','cancelled'))
    return c.job(job['id'])
timers=[];calls=[];case='full';cid=0
def send(kind,payload=b''):
    global cid
    seq=len(calls);calls.append((kind,payload))
    e.command_results[seq]=dict(state='acknowledged',code=0,ack_at=time.monotonic())
    if kind==P.CAPTURE:
        cid+=1;current=cid;mode=case
        def receive():
            if mode=='disconnect':e.ready=False;return
            if mode=='none':return
            zero=np.zeros((32,5),dtype='<i2')
            offsets=list(reversed(range(0,2048,32))) if mode=='full' else [0]
            if mode=='partial':e.parser.errors+=1;e.gaps+=1
            for offset in offsets:
                e.ingest(P.pack(P.AUDIO,struct.pack('<HHHI',current,offset,2048,48000)+zero.tobytes(),seq=offset))
        timer=threading.Timer(.06,receive);timers.append(timer);timer.start()
    return seq
try:
    w.demo();wait(lambda:e.ready);wait(lambda:c.active is None);w.refresh_agent();w.refresh()
    original_draw=w.draw_live;draws=[]
    def draw(a,fs):draws.append(e.audio_revision);original_draw(a,fs)
    w.draw_live=draw
    ping=w.submit_command('ping');done(ping);w.refresh_agent();w.refresh()
    assert not draws,'ordinary command repainted unchanged samples'
    # Race: a new frame arrives during drawing. It must not be marked as drawn.
    def race(a,fs):original_draw(a,fs);e.make_demo_audio()
    w.draw_live=race;e.make_demo_audio();previous=e.audio_revision;w.refresh()
    assert w.revision==previous and e.audio_revision>previous
    w.draw_live=draw;w.refresh();assert w.revision==e.audio_revision
    w.pause.setChecked(True);e.make_demo_audio();previous=w.revision;w.refresh();assert w.revision==previous
    w.pause.setChecked(False);w.refresh();assert w.revision==e.audio_revision
    e.source='测试假串口（非实物）';e.ready=True;e.send=send;c.capture_timeout_s=.12
    first=w.submit_command('capture',{'trigger':0});repeat=w.submit_command('capture',{'trigger':0})
    assert first['id']==repeat['id'],'duplicate capture queued'
    try:w.submit_command('capture',{'trigger':1})
    except ValueError:pass
    else:raise AssertionError('different trigger silently coalesced')
    result=done(first);assert result['state']=='completed' and result['result']['silent']
    w.refresh();assert '当前采样为静音' in w.audio_note.text()
    w.service_live();assert 'CRC增加' in w.live_note.toolTip()
    assert sum(k==P.CAPTURE for k,p in calls)==1
    d=e.capture_diagnostics[-1];assert d['ack_ms'] is not None and d['receive_ms'] is not None and d['draw_ms'] is not None
    old=e.audio.copy();revision=e.audio_revision
    for case,trigger,expected in [('partial',0,'报文不完整'),('none',1,'过零触发等待超时'),('none',0,'立即抓取超时'),('disconnect',0,'通信失败')]:
        result=done(w.submit_command('capture',{'trigger':trigger}))
        assert result['state']=='failed' and expected in result['message'],result
        assert e.audio_revision==revision and np.array_equal(e.audio,old)
        if case=='partial':assert e.capture_diagnostics[-1]['crc_delta']==1
    assert all(d['total_ms']>=0 for d in e.capture_diagnostics)
    print('PASS duplicate capture, ack/data/draw diagnostics, partial/trigger/disconnect errors, silent capture, preserved data, repaint race and pause')
finally:
    for timer in timers:timer.join(1)
    w.close()
