"""Reproducible packaged-EXE diagnostic check. Synthetic frames, no serial access."""
import json,struct,time,sys,subprocess
from pathlib import Path
from unittest.mock import patch
from PySide6 import QtCore as C
import lab_protocol as P

def fixture():
    b=bytearray(496);b[0]=10;b[1]=1;b[11]=8;b[77]=8;b[236]=1
    struct.pack_into('<HH',b,180,1500,1500);struct.pack_into('<HH',b,187,134,134)
    flags=1|2|8|16|128|(3<<8)|(50<<12)|(3<<18)|(3<<22)
    struct.pack_into('<I',b,288,flags);struct.pack_into('<hhh',b,292,-320,-160,160)
    struct.pack_into('<3H',b,320,200,50,200);struct.pack_into('<4I',b,330,50000,100000,50000,50000)
    struct.pack_into('<h',b,346,-768);b[480]=1;b[362]=2;b[363]=1
    struct.pack_into('<H',b,364,400);struct.pack_into('<I',b,366,25);b[370]=3;b[371]=3
    struct.pack_into('<IIh',b,372,1000,1350,-320);struct.pack_into('<I',b,304,1)
    ev=bytearray(32);ev[:8]=bytes([1,0,3,0,0,64,1,1]);struct.pack_into('<5I',ev,8,1,50000000,1350,1000,0)
    return bytes(b),bytes(ev)

def start(w,app,out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    def check():
        try:
            e=w.engine;e.demo_duo();e.device='DUO04-LIVE 2.1+GEST26';e.source='模拟诊断（合成帧，非硬件）';e.enable_duo_capabilities()
            b,ev=fixture();e.start_record(out/'模拟记录')
            e.ingest(P.pack(136,b,0));e.ingest(P.pack(140,ev,1));e.stop_record()
            assert e.parser.errors==0 and e.instrument_state['diagnostic'][0]['linear_hz']==400
            assert e.hit_events[-1]['snapshot_age_ms']==35
            w.tabs.setCurrentIndex(w.duo_page_index);w.resize(1600,1100);w.refresh();w.refresh_agent();app.processEvents()
            from lab_diagnostic import refresh,export_csv,decode_event
            refresh(w);assert '400Hz' in w.diag_cards[0].text() and '下拍' in w.diag_events.toPlainText()
            with patch('PySide6.QtWidgets.QFileDialog.getSaveFileName',return_value=(str(out/'诊断.csv'),'CSV')):export_csv(w)
            w.grab().save(str(out/'诊断页.png'))
            # Teaching / legacy mode doesn't claim a pre-strike snapshot.
            legacy=bytearray(ev);legacy[7]=0;assert decode_event(legacy)['snapshot_age_ms'] is None
            e.device='DUO04-LIVE 2.1+GEST25';e.enable_duo_capabilities();refresh(w);assert not w.diag_yaw_invert.isEnabled()
            e.device='DUO04-LIVE 2.1+GEST26';e.enable_duo_capabilities()
            w.start_agent()
            command=[str(Path(sys.executable).parent/'TangLabCtl.exe')] if getattr(sys,'frozen',False) else [sys.executable,str(Path(__file__).parent/'tanglabctl.py')]
            child=subprocess.run(command+['--session',str(w.agent.session_path),'status'],capture_output=True,text=True,encoding='utf8',timeout=8,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            assert child.returncode==0,child.stderr
            # Responses contain no session token; retain only summarized checks.
            result=json.loads(child.stdout);assert result
            replay=__import__('lab_engine').LabEngine();replay.replay(out/'模拟记录');replay.thread.join(3)
            assert not replay.thread.is_alive() and replay.hit_events[-1]['snapshot_age_ms']==35 and replay.instrument_state['diagnostic'][0]['linear_hz']==400
            replay.close()
            (out/'result.json').write_text(json.dumps(dict(result='PASS',basis='模拟合成帧，非上板',checks=['GEST26状态及事件解码','400Hz/2.5ms读数','诊断与事件显示','CSV导出','旧固件禁用方向设置','原始记录回放','GUI EXE与CLI联动'],cli_exit_code=child.returncode),ensure_ascii=False,indent=2),encoding='utf8')
        except Exception as exc:
            (out/'result.json').write_text(json.dumps(dict(result='FAIL',error=repr(exc)),ensure_ascii=False),encoding='utf8');app.exit(1)
        finally:
            w.close()
    C.QTimer.singleShot(300,check)
