from pathlib import Path
import sys,time,json,struct
SRC=Path(__file__).resolve().parent;sys.path.insert(0,str(SRC));W=SRC/'validation-work';W.mkdir(exist_ok=True)
from lab_engine import LabEngine
from lab_gesture import encode,decode,payload
from lab_agent import CommandController
e=LabEngine();ctl=CommandController(e,W/'host-unit')
(W/'host-unit').mkdir(exist_ok=True)
try:
 ctl.execute({'cancel':__import__('threading').Event(),'history':[]},'instrument.demo',{})
 assert e.capabilities['gesture_v24']
 b=encode(dict(enabled=[True,True],invert=[True,False],pressed=[True,False],fresh=[True,False],octave_codes=[2,1],snapshot_codes=[3,0],bend_cents=[-2400,2400],group_serial=[65535,0],pitch_degrees=[-90,90]))
 d=decode(b);assert d['bend_cents']==[-2400,2400] and d['pitch_degrees']==[-90,90]
 for action,p in [('gesture.test',dict(hand=2)),('gesture.test',dict(hand=0,pitch_degrees=float('nan'))),('gesture.configure',dict(enabled=[True]))]:
  try:payload(action,p)
  except ValueError:pass
  else:raise AssertionError('malformed input accepted')
 e.send(60,struct.pack('<BH',0,1));e.send(48,__import__('lab_duo').config_payload({'run':True},True,True,True)[1])
 e.send(65,payload('gesture.test',dict(hand=0))[1]);e.send(50,__import__('lab_duo').strike_payload(dict(hand=0,zone=0,capture=False),1)[0])
 e.send(65,payload('gesture.test',dict(hand=0,pressed=True))[1]);e.send(65,payload('gesture.test',dict(hand=0,pressed=True,pitch_degrees=15))[1]);e.send(17,b'\0\0\x02')
 assert e.audio_metadata['gesture']['pressed'][0] and e.audio_metadata['gesture']['bend_cents'][0]==600
 frozen=json.loads(json.dumps(e.audio_metadata));e.send(65,payload('gesture.test',dict(hand=0,pressed=False,pitch_degrees=15))[1]);assert e.audio_metadata==frozen
 record=W/'host-unit'/('recording-'+str(time.time_ns()));e.start_record(record);e.record_demo_capture();e.stop_record()
 e.replay(record);e.thread.join(10)
 assert e.status=='回放完成' and e.audio.shape==(512,5),e.status
 assert e.audio_metadata['gesture']['pressed'][0] and e.audio_metadata['gesture']['bend_cents'][0]==600,e.audio_metadata
 e.device='DUO04-LIVE 2.1';e.enable_duo_capabilities();assert not e.capabilities['gesture_v24']
 result=dict(result='PASS',checks=['wire encode/decode','invalid params','frozen capture metadata','512 point recording/replay retains gesture','old firmware gating'],source='simulation')
 (W/'host-unit/result.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(result)
finally:
 ctl.closed.set();e.close()
