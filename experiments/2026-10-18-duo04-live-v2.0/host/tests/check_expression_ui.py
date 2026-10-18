"""GUI/API expression selection is explicit and remains off on old firmware."""
import os,sys,time
from pathlib import Path
os.environ['QT_QPA_PLATFORM']='offscreen';sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tanglab import Window,W
from PySide6.QtTest import QTest
from lab_expression import expression_payload,decode_expression
app=W.QApplication([]);w=Window()
def run(a,p=None):
 j=w.submit_command(a,p or {});end=time.monotonic()+5
 while w.controller.job(j['id'])['state'] not in ('completed','failed','cancelled'):
  QTest.qWait(15)
  if time.monotonic()>end:raise AssertionError('timeout')
 return w.controller.job(j['id'])
try:
 assert all(not g[0].isChecked() and not g[3].isChecked() for g in w.duo_expression)
 assert run('duo.demo')['state']=='completed';w.refresh_duo()
 assert w.engine.capabilities['duo_expression']
 left=w.duo_expression[0];left[0].setChecked(True);left[1].setValue(6);left[2].setValue(35);left[3].setChecked(True);left[4].setValue(200)
 settings=w.duo_settings(True);j=run('duo.configure',settings);assert j['state']=='completed',j
 e=w.engine.expression;assert e[0]['vibrato'] and e[0]['glide'] and not e[1]['glide']
 assert e[0]['glide_ms']==200 and e[0]['vibrato_cents']==35
 cfg,wire=expression_payload({'hands':[{'glide':True,'glide_ms':200},{'vibrato':True,'vibrato_cents':40}]});assert len(wire)==16
 parsed=decode_expression(wire);assert parsed[0]['glide_ms']==200 and parsed[1]['vibrato_cents']==40
 w.engine.device='DUO02-MOUSE 1.3';w.engine.enable_duo_capabilities();w.refresh_duo()
 assert not left[0].isEnabled() and not left[3].isEnabled()
 assert run('duo.expression',{'hands':[{},{}]})['state']=='failed'
 print('PASS independent optional glide/vibrato defaults, GUI parameters, ACK dispatcher and old firmware rejection')
finally:w.close();app.processEvents()
