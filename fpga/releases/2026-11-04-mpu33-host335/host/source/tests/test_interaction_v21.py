"""Run explicitly: python tests/test_interaction_v21.py OUTPUT_DIR. No serial open."""
from pathlib import Path
import sys,json,time,threading
from urllib.request import Request,build_opener,ProxyHandler
from urllib.error import HTTPError
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from lab_engine import LabEngine
from lab_agent import CommandController,AgentServer
from lab_interaction import payload,simulation_tick

def main(out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    e=LabEngine();c=CommandController(e,out);server=AgentServer(c)
    results={}
    def command(action,p=None,expected='completed'):
        j=c.submit(action,p);end=time.monotonic()+5
        while time.monotonic()<end:
            j=c.job(j['id'])
            if j['state'] in ('completed','failed','cancelled'):
                assert j['state']==expected,(action,j['message']);return j
            time.sleep(.01)
        raise TimeoutError(action)
    try:
        command('instrument.demo');assert e.capabilities['interaction_v21']
        before=e.seq
        for action,p in [('ui.action',{'action':'shell'}),('lesson.configure',{'source':'mouse','lesson':9}),('lesson.control',{'action':'run'}),('ui.action',{'action':'key0','extra':1})]:
            try:payload(action,p)
            except ValueError:continue
            raise AssertionError('invalid input accepted')
        assert e.seq==before;results['validation']='PASS'
        command('lesson.configure',{'source':'mouse','lesson':0});command('lesson.control',{'action':'start'})
        command('duo.strike',{'hand':1,'zone':0});command('duo.strike',{'hand':0,'zone':0});command('duo.strike',{'hand':0,'zone':0})
        assert e.instrument_state['correct']==1 and e.instrument_state['wrong']==1
        command('lesson.control',{'action':'pause'});time.sleep(.3);simulation_tick(e);assert e.instrument_state['position']==0
        command('lesson.control',{'action':'resume'});time.sleep(.3);simulation_tick(e);assert e.instrument_state['position']==1
        command('ui.action',{'action':'key2'});assert e.instrument_state['active_hand']==1
        command('ui.action',{'action':'key1'});assert e.duo_config['presets'][1]==1
        command('capture',{'points':512});assert e.audio.shape==(512,5)
        e.start_record(out/'recording');e.record_demo_capture();e.stop_record()
        results['lesson_and_capture']='PASS simulated'
        info=server.start();opener=build_opener(ProxyHandler({}))
        try:opener.open(info['url']+'/api/v1/status',timeout=2)
        except HTTPError as exc:assert exc.code==401
        else:raise AssertionError('unauthenticated request accepted')
        req=Request(info['url']+'/api/v1/capabilities',headers={'Authorization':'Bearer '+info['token']})
        commands=json.load(opener.open(req,timeout=2))['commands']
        assert all(k in commands for k in ('ui.action','lesson.configure','lesson.control'));results['http_auth']='PASS'
        try:c.wait({'cancel':threading.Event()},lambda:False,.02,'expected timeout')
        except TimeoutError:results['timeout']='PASS'
        else:raise AssertionError('timeout not raised')
        command('lesson.control',{'action':'stop'})
        e.device='DUO04-LIVE 2.0';e.enable_duo_capabilities();before=e.seq
        command('ui.action',{'action':'confirm'},'failed');assert before==e.seq;results['old_firmware_gating']='PASS'
        e.replay(out/'recording');end=time.monotonic()+6
        while time.monotonic()<end and e.status!='回放完成':time.sleep(.02)
        assert e.status=='回放完成' and e.audio.shape==(512,5),e.status
        assert e.instrument_state['position']==1;results['replay']='PASS simulated recording'
    finally:
        server.stop();c.shutdown();e.close()
    (out/'result.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(results,ensure_ascii=False))
if __name__=='__main__':main(sys.argv[1])
