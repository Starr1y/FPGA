"""Packaged GUI smoke check, explicitly simulated and opt-in."""
import json,time,sys,subprocess
from pathlib import Path
from PySide6 import QtCore as C

def start(window,app,out,instrument=False):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    actions=[('duo.demo',{}),('duo.expression',{'hands':[{'glide':True,'glide_ms':200},{'vibrato':True,'vibrato_hz':5.5,'vibrato_cents':20}]}),('monitor.select',{'voices':[0,16,31]}),('sine.start',{}),('capture',{'points':512}),('sine.stop',{}),('duo.configure',{'run':True}),
             ('duo.strike',{'hand':0,'zone':2,'capture':True}),
             ('duo.strike',{'hand':1,'zone':4,'capture':True}),
             ('capture',{'points':2048})]
    if instrument:actions[0:1]=[('instrument.demo',{}),('instrument.set',{'mode':0,'left_timbre':1,'left_hold_ms':1000}),('instrument.set',{'lesson':2,'lesson_start':True}),('instrument.set',{'mode':1})]
    state={'job':None,'index':0};deadline=time.monotonic()+30
    window.tabs.setCurrentIndex(window.duo_page_index)
    def tick():
        try:
            if time.monotonic()>deadline:raise TimeoutError('鼠标页程序验证超时')
            if state['job']:
                j=window.controller.job(state['job'])
                if j['state'] not in ('completed','failed','cancelled'):return
                assert j['state']=='completed',j
                state['job']=None
            if state['index']<len(actions):
                a,p=actions[state['index']];state['index']+=1
                state['job']=window.submit_command(a,p)['id'];return
            window.refresh_duo();window.refresh()
            assert window.engine.audio.shape==(2048,5)
            assert window.engine.duo['hits']==[1,1]
            window.write_audio(out/'鼠标完整采样.csv');window.write_history(out/'鼠标采样历史.csv')
            window.start_agent()
            root=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
            cli=[str(root/'TangLabCtl.exe')] if getattr(sys,'frozen',False) else [sys.executable,str(root/'tanglabctl.py')]
            p=subprocess.run(cli+['--session',str(window.agent.session_path),'status'],capture_output=True,text=True,encoding='utf-8',timeout=5,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            assert p.returncode==0,p.stderr
            status=json.loads(p.stdout);assert status['capabilities']['duo_expression']
            if instrument:assert status['capabilities']['instrument'] and window.instrument_group.isEnabled() and window.duo_presets[0].count()==4
            assert window.engine.expression[0]['glide'] and window.engine.expression[1]['vibrato']
            assert window.engine.voice_audio.shape==(2048,3) and len(window.voice_tiles)==32
            export=out/'导出';export.mkdir(exist_ok=True);window.controller.export_to(export)
            window.engine.start_record(out/'recording');window.engine.record_demo_capture();window.engine.stop_record()
            (out/'cli-status.json').write_text(p.stdout,encoding='utf-8')
            window.grab().save(str(out/'鼠标测试页.png'))
            (out/'result.json').write_text(json.dumps(dict(result='PASS',source='模拟，非实测',
                 device=window.engine.device,hits=window.engine.duo['hits'],shape=list(window.engine.audio.shape),
                 channels=window.engine.channel_names,monitor_voices=window.engine.audio_metadata.get('monitor_voices'),shared_dock=window.monitor_dock.isVisible()),ensure_ascii=False,indent=2),encoding='utf-8')
            window.duo_smoke_timer.stop();window.close()
        except Exception as exc:
            (out/'result.json').write_text(json.dumps(dict(result='FAIL',error=str(exc)),ensure_ascii=False),encoding='utf-8')
            window.duo_smoke_timer.stop();window.close();app.exit(1)
    window.duo_smoke_timer=C.QTimer(window);window.duo_smoke_timer.timeout.connect(tick);window.duo_smoke_timer.start(30)
