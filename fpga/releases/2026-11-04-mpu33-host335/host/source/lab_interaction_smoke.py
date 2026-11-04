"""Opt-in simulated GUI/CLI integration check; never opens a hardware port."""
from pathlib import Path
import json,time,subprocess,sys
from PySide6 import QtCore as C
def start(w,app,out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    actions=[('instrument.demo',{}),('lesson.configure',{'source':'mouse','lesson':0}),('lesson.control',{'action':'start'}),
             ('duo.strike',{'hand':1,'zone':0,'capture':True}),('duo.strike',{'hand':0,'zone':0,'capture':True}),
             ('lesson.control',{'action':'pause'}),('lesson.control',{'action':'resume'}),
             ('ui.action',{'action':'key2'}),('ui.action',{'action':'key1'}),('capture',{'points':512})]
    state={'i':0,'job':None,'settle':None};deadline=time.monotonic()+35;logs=[]
    w.tabs.setCurrentIndex(w.duo_page_index)
    def tick():
        try:
            if time.monotonic()>deadline:raise TimeoutError('2.1模拟验证超时')
            if state['job']:
                j=w.controller.job(state['job'])
                if j['state'] not in ('completed','failed','cancelled'):return
                if j['state']!='completed':raise AssertionError((j['action'],j['message']))
                logs.append({'action':j['action'],'state':j['state']});state['job']=None
            if state['i']<len(actions):
                a,p=actions[state['i']];state['i']+=1;state['job']=w.submit_command(a,p)['id'];return
            if state['settle'] is None:state['settle']=time.monotonic()+.4;return
            if time.monotonic()<state['settle']:return
            w.refresh_duo();e=w.engine;s=e.instrument_state
            assert s['correct']==1 and s['wrong']==1 and s['position']==1,s
            assert s['active_hand']==1 and e.duo_config['presets'][1]==1,s
            assert e.audio.shape==(512,5) and w.interaction_group.isEnabled()
            assert w.duo_fans[0].lesson_target==1
            w.write_audio(out/'教学采样.csv');w.write_history(out/'教学历史.csv')
            e.start_record(out/'recording');e.record_demo_capture();e.stop_record()
            w.start_agent();root=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
            cli=[str(root/'TangLabCtl.exe')] if getattr(sys,'frozen',False) else [sys.executable,str(root/'tanglabctl.py')]
            result=subprocess.run(cli+['--session',str(w.agent.session_path),'status'],capture_output=True,text=True,encoding='utf-8',timeout=8,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            assert result.returncode==0,result.stderr
            assert json.loads(result.stdout)['capabilities']['interaction_v21']
            w.monitor_dock.hide();w.resize(1360,1000);app.processEvents();w.grab().save(str(out/'教学上位机.png'))
            (out/'导出').mkdir(exist_ok=True);w.controller.export_to(out/'导出')
            e.send(63,b'\0');w.interaction_timer.stop();w.close()
            (out/'result.json').write_text(json.dumps(dict(result='PASS',source='模拟，非板卡实测',commands=logs,correct=s['correct'],wrong=s['wrong'],position=s['position'],audio=[512,5],cli='PASS'),ensure_ascii=False,indent=2),encoding='utf-8')
        except Exception as exc:
            (out/'result.json').write_text(json.dumps(dict(result='FAIL',error=str(exc)),ensure_ascii=False,indent=2),encoding='utf-8')
            w.interaction_timer.stop();w.close();app.exit(1)
    w.interaction_timer=C.QTimer(w);w.interaction_timer.timeout.connect(tick);w.interaction_timer.start(40)
