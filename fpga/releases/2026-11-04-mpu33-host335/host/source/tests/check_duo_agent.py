"""Authenticated DUO API, capture fairness and recording round trip."""
import sys,time,tempfile,threading,json
from pathlib import Path
from urllib.request import urlopen
from urllib.error import HTTPError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from lab_engine import LabEngine
from lab_agent import CommandController,AgentServer
from tanglabctl import Client

base=Path(sys.argv[1]);base.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(dir=base) as temp:
    e=LabEngine();c=CommandController(e,temp);s=AgentServer(c)
    try:
        info=s.start();client=Client(s.session_path)
        try:urlopen(info['url']+'/api/v1/status',timeout=2);raise AssertionError('missing auth accepted')
        except HTTPError as exc:assert exc.code==401
        def run(a,p=None):
            j=client.run(a,p or {},8);assert j['state']=='completed',j
            return j['result']
        run('duo.demo');run('duo.configure')
        original=c.capture;entered=threading.Event();release=threading.Event()
        def slow(*args,**kwargs):
            entered.set();assert release.wait(3);return original(*args,**kwargs)
        c.capture=slow
        job=client.run('capture',{'points':2048},no_wait=True);assert entered.wait(1)
        strike=run('duo.strike',{'hand':0,'zone':1,'capture':True})
        assert e.audio_metadata['event_id']==strike['event_id']
        assert c.job(job['id'])['state']=='running','strike snapshot must not satisfy ordinary capture'
        run('duo.stop');assert not e.duo['running']
        release.set()
        end=time.monotonic()+3
        while c.job(job['id'])['state'] not in ('completed','failed') and time.monotonic()<end:time.sleep(.01)
        assert c.job(job['id'])['state']=='completed'
        c.capture=original
        record=Path(temp)/'录制';e.start_record(record)
        run('duo.configure');run('duo.strike',{'hand':1,'zone':2,'capture':True})
        expected=e.audio.copy();meta=dict(e.audio_metadata);e.stop_record()
        run('replay',{'path':str(record)})
        import numpy as np
        assert np.array_equal(e.audio,expected) and e.audio_metadata['event_id']==meta['event_id']
        assert e.channel_names[0]=='干声左' and e.capabilities['duo_mouse']
        (base/'agent-result.json').write_text(json.dumps(dict(result='PASS',basis='模拟，非实物',
            authentication=True,capture_does_not_block_strike_or_stop=True,record_replay=True),ensure_ascii=False,indent=2),encoding='utf-8')
        print('PASS DUO auth, capture/strike/stop fairness, event association, Chinese-path record/replay')
    finally:s.stop();c.shutdown();e.close()
