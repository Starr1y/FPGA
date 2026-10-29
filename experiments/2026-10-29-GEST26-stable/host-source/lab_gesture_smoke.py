import time,json,sys,subprocess
from pathlib import Path
from PySide6 import QtCore as C

def start(w,app,out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True);w.gesture_timer.stop()
    actions=[('instrument.demo',{}),('gesture.configure',{}),('instrument.set',{'mode':1}),('duo.configure',{'run':True,'gain':8,'mouse_basic':False}),
        ('gesture.test',{'hand':0,'pressed':False,'pitch_degrees':0}),('duo.select',{'hand':0,'zone':0}),
        ('duo.strike',{'hand':0,'zone':0,'capture':False}),('gesture.test',{'hand':0,'pressed':True,'pitch_degrees':0}),
        ('gesture.test',{'hand':0,'pressed':True,'pitch_degrees':15}),('capture',{'points':512}),
        ('record.start',{'name':'手势模拟测试-'+str(time.time_ns())}),('capture',{'points':2048}),('record.stop',{}),
        ('gesture.test',{'hand':0,'pressed':False,'pitch_degrees':15}),('duo.stop',{})]
    state={'i':0,'job':None};deadline=time.monotonic()+40;log=[];w.tabs.setCurrentIndex(w.duo_page_index)
    def tick():
        try:
            if time.monotonic()>deadline:raise TimeoutError('手势联合检查超时')
            if state['job']:
                j=w.controller.job(state['job'])
                if j['state'] not in ('completed','failed','cancelled'):return
                if j['state']!='completed':raise AssertionError((j['action'],j['message']))
                log.append(j);state['job']=None
            if state['i']<len(actions):
                a,p=actions[state['i']];state['i']+=1;state['job']=w.submit_command(a,p)['id'];return
            e=w.engine
            assert e.capabilities['gesture_v24'] and e.audio.shape==(2048,5)
            assert 'gesture' in e.audio_metadata and e.audio_metadata['gesture']['bend_cents'][0]==600 and e.audio_metadata['gesture']['pressed'][0]
            (out/'导出').mkdir(exist_ok=True);w.controller.export_to(out/'导出');w.refresh();w.monitor_dock.hide();w.resize(1400,1100);app.processEvents();w.grab().save(str(out/'手势测试页.png'))
            w.start_agent();cli=Path(sys.executable).parent/'TangLabCtl.exe' if getattr(sys,'frozen',False) else None
            args=[str(cli)] if cli else [sys.executable,str(Path(__file__).parent/'tanglabctl.py')]
            p=subprocess.run(args+['--session',str(w.agent.session_path),'status'],capture_output=True,text=True,encoding='utf8',timeout=8,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            (out/'cli-check.json').write_text(json.dumps(dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr),ensure_ascii=False),encoding='utf8')
            assert p.returncode==0,(p.stdout,p.stderr)
            assert json.loads(p.stdout)['capabilities']['gesture_v24']
            (out/'result.json').write_text(json.dumps(dict(result='PASS',source='模拟，非实测',shape=[2048,5],cli='PASS',commands=[(j['action'],j['state']) for j in log],metadata=e.audio_metadata),ensure_ascii=False,indent=2),encoding='utf8')
            timer.stop();w.close()
        except Exception as exc:
            (out/'result.json').write_text(json.dumps(dict(result='FAIL',error=repr(exc),trace=__import__('traceback').format_exc()),ensure_ascii=False),encoding='utf8');timer.stop();w.close();app.exit(1)
    timer=C.QTimer(w);timer.timeout.connect(tick);timer.start(40);w.gesture_smoke_timer=timer
