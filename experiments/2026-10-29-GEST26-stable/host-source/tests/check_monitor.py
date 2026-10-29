"""1.3 focused GUI/collector/agent regression; all stimuli explicitly simulated."""
import os,sys,time,json,struct,tempfile
from pathlib import Path
os.environ['QT_QPA_PLATFORM']='offscreen';sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from tanglab import Window,W,C
from PySide6.QtTest import QTest
from lab_engine import LabEngine
from lab_monitor import sine_payload,monitor_payload
import lab_protocol as P
app=W.QApplication([]);w=Window();results=[]
def wait(fn,t=8):
 end=time.monotonic()+t
 while not fn():
  QTest.qWait(15)
  if time.monotonic()>end:raise AssertionError('等待超时')
def command(a,p=None):
 j=w.submit_command(a,p or {});wait(lambda:w.controller.job(j['id'])['state'] in ('completed','failed','cancelled'));r=w.controller.job(j['id']);assert r['state']=='completed',r;return r
try:
 command('duo.demo');w.refresh_duo();assert w.engine.capabilities['duo_monitor']
 command('monitor.select',{'voices':[0,16,31]});command('sine.start');command('capture',{'points':512});w.refresh_duo()
 assert w.engine.sine_state['enabled'] and w.engine.audio.shape==(512,5) and w.engine.voice_audio.shape==(512,0)
 assert w.engine.audio_metadata['calibration'] and np.max(abs(w.engine.audio[:,2]))>1000
 command('sine.stop');assert not w.engine.sine_state['enabled'] and not w.engine.duo_config['run']
 command('duo.configure',{'run':True});command('duo.strike',{'hand':0,'zone':0,'capture':True});w.refresh_duo()
 assert w.engine.voice_audio.shape==(512,3) and np.any(w.engine.voice_audio[:,0])
 assert len(w.voice_tiles)==32 and w.monitor_plot_ids==[0,16,31]
 # Floating application-owned scope is safe; external state calls stop.
 w.show();w.monitor_dock.setFloating(True);w.monitor_dock.show();w.monitor_dock.activateWindow();QTest.qWait(80)
 assert w.engine.duo_config['run'],'floating dock muted performance'
 w.tabs.setCurrentIndex(1);w.refresh_duo();assert w.monitor_dock.isVisible() and not w.table.isEnabled()
 w.monitor_dock.setFloating(False)
 # Shared pause freezes raw voice and stereo waveforms.
 w.refresh_duo();prior=w.monitor_voice_lines[0].yData.copy();w.pause.setChecked(True)
 command('capture',{'points':2048});w.refresh_duo();assert np.array_equal(prior,w.monitor_voice_lines[0].yData)
 w.pause.setChecked(False);w.refresh_duo();assert len(w.monitor_voice_lines[0].yData)==2048
 with tempfile.TemporaryDirectory() as folder:
  root=Path(folder);w.engine.start_record(root/'记录');command('capture',{'points':512});expected=w.engine.voice_audio.copy();w.engine.stop_record()
  replay=LabEngine();replay.replay(root/'记录');wait(lambda:not replay.thread.is_alive());assert replay.status=='回放完成',replay.status
  assert np.array_equal(replay.voice_audio,expected) and replay.audio_metadata['monitor_voices']==[0,16,31];replay.close()
  # Deliberately omit final selected-voice frame: previous complete capture must remain.
  lines=[json.loads(x) for x in (root/'记录/raw.jsonl').read_text(encoding='utf-8').splitlines()]
  frames=[f for line in lines if line['type']=='rx' for f in P.Parser().feed(bytes.fromhex(line['hex']))]
  assert any(f.kind==138 for f in frames)
  e=LabEngine();e.device='DUO02-MOUSE 1.3';e.enable_duo_capabilities();e.audio=np.ones((4,5),np.int16);old=e.audio.copy();rev=e.audio_revision
  last_voice=max(i for i,f in enumerate(frames) if f.kind==138)
  # Use only the final capture (record start also stores current simulated capture).
  last_meta=max(i for i,f in enumerate(frames) if f.kind==137);sub=frames[last_meta:]
  for f in sub[:-1]:e.frame(f)
  assert e.audio_revision==rev and np.array_equal(e.audio,old),'partial capture replaced valid wave'
  e.frame(sub[-1]);assert e.audio_revision==rev+1 and np.array_equal(e.voice_audio,expected)
  c=w.controller.export_to(root/'导出') if False else None
  (root/'导出').mkdir();r=w.controller.export_to(root/'导出');assert (root/'导出/所选声部PCM.csv').is_file()
  w.write_history(root/'历史.csv');assert '声部32_PCM' in (root/'历史.csv').read_text(encoding='utf-8-sig')
 command('duo.stop');w.monitor_mode.setCurrentIndex(0);w.toggle_monitor_live();wait(lambda:w.engine.audio_count>=5);w.monitor_mode.setCurrentIndex(1);assert not w.live_running and w.duo_sync.isChecked()
 for bad in ({'voices':[1,1]},{'voices':[32]},{'voices':list(range(5))}):
  try:monitor_payload(bad);raise AssertionError('invalid monitor accepted')
  except ValueError:pass
 print('PASS simulated: calibration, selected PCM, 32 tiles, shared dock/focus, pause, record/replay, incomplete frame, exports, exclusive modes')
finally:w.close();app.processEvents()
