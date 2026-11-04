"""Opt-in packaged GUI/CLI check. All input is simulated, never opens COM."""
import json,time,sys,subprocess,struct
from pathlib import Path
from PySide6 import QtCore as C
from lab_score import ASSETS,load_score

def start(w,app,out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    score=load_score(ASSETS/'半音练习.tangscore.json')
    actions=[('score.demo',{}),('score.upload',{'score':score}),('score.status',{}),
             ('lesson.configure',{'source':'mouse','lesson':3}),('lesson.control',{'action':'start'})]
    state={'i':0,'job':None,'stage':0};logs=[];deadline=time.monotonic()+50
    def submit(a,p):state['job']=w.submit_command(a,p)['id']
    def tick():
        try:
            if time.monotonic()>deadline:raise TimeoutError('曲谱模拟验证超时')
            if state['job']:
                j=w.controller.job(state['job'])
                if j['state'] not in ('completed','failed','cancelled'):return
                assert j['state']=='completed',(j['action'],j['message'])
                logs.append({'action':j['action'],'result':j.get('result')});state['job']=None
            if state['i']<len(actions):
                a,p=actions[state['i']];state['i']+=1;submit(a,p);return
            e=w.engine;s=e.instrument_state
            if state['stage']==0:
                assert e.score_state['loaded'] and e.score_state['total']==6
                assert s['target_note']==36 and s['target_hand']==1,s
                state['stage']=1;submit('duo.strike',dict(hand=0,zone=0,profile=2,octave=0,capture=False));return
            if state['stage']==1:
                assert s['wrong']==1 and s['position']==0,s
                state['stage']=2;submit('duo.strike',dict(hand=1,zone=0,profile=2,octave=0,capture=False));return
            if state['stage']==2:
                assert s['correct']==1,s
                state['stage']=3;submit('lesson.control',{'action':'pause'});return
            if state['stage']==3:
                if 'paused_until' not in state:state['paused_until']=time.monotonic()+.35;return
                if time.monotonic()<state['paused_until']:return
                assert s['position']==0,s
                state['stage']=4;submit('lesson.control',{'action':'resume'});return
            if state['stage']==4:
                if s['position']==0:return
                assert s['position']==1 and s['target_note']==49,s
                state['stage']=5;submit('capture',{'points':512});return
            if state['stage']==5:
                assert e.audio.shape==(512,5)
                from lab_score_ui import set_score
                set_score(w,score);__import__('lab_score_import').checked(w);w.tabs.setCurrentIndex(w.tabs.count()-1);w.monitor_dock.hide();w.resize(1500,1050);w.refresh();app.processEvents()
                assert w.score_table.rowCount()==6
                w.grab().save(str(out/'曲谱上传教学页.png'))
                w.write_audio(out/'模拟教学采样.csv');w.write_history(out/'模拟教学历史.csv')
                # Verify versioned score frame recording/replay, independent of simulator state.
                b=bytearray(48);b[:4]=bytes([1,1,0,0]);struct.pack_into('<IHH',b,4,e.score_state['crc32'],6,1);b[12:20]=bytes([2,1,49,1,3,0,0,1]);struct.pack_into('<H',b,38,333)
                import lab_protocol as P
                e.start_record(out/'模拟记录');e.ingest(P.pack(141,b,501));e.record_demo_capture();e.stop_record()
                from lab_engine import LabEngine
                r=LabEngine();r.replay(out/'模拟记录');r.thread.join(4);assert r.score_state['total']==6 and r.score_state['note']==49;r.close()
                w.start_agent();cli=[str(Path(sys.executable).parent/'TangLabCtl.exe')] if getattr(sys,'frozen',False) else [sys.executable,str(Path(__file__).parent/'tanglabctl.py')]
                child=subprocess.run(cli+['--session',str(w.agent.session_path),'run','score.status'],capture_output=True,text=True,encoding='utf8',timeout=10,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
                assert child.returncode==0,child.stderr+child.stdout
                result=json.loads(child.stdout);assert result['result']['score']['total']==6
                # Old firmware must not expose upload capability.
                e.device='DUO04-LIVE 2.1+GEST26';e.enable_duo_capabilities();assert not e.capabilities.get('score_v1')
                (out/'result.json').write_text(json.dumps(dict(result='PASS',basis='全程模拟，非上板实测',checks=['GUI第09页','CRC上传与全读回','半音布局与C2/C3自动档','错误手不推进','正确反馈','暂停恢复','512点采样与CSV','曲目状态记录回放','GUI与CLI联合启动','旧固件能力禁用'],commands=logs),ensure_ascii=False,indent=2),encoding='utf8')
                w.score_test_timer.stop();w.close()
        except Exception as exc:
            import traceback
            (out/'result.json').write_text(json.dumps(dict(result='FAIL',error=repr(exc),traceback=traceback.format_exc()),ensure_ascii=False,indent=2),encoding='utf8');w.score_test_timer.stop();w.close();app.exit(1)
    w.score_test_timer=C.QTimer(w);w.score_test_timer.timeout.connect(tick);w.score_test_timer.start(40)
