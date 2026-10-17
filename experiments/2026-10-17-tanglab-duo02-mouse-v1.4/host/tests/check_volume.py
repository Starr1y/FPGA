import sys,struct
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from lab_engine import LabEngine
import lab_protocol as P
e=LabEngine()
assert all(not v['gate'] and v['gain']==.002 for v in e.voices)
v=e.voices[0].copy();v['gate']=True
fine=P.voice_payload(0,**v,fine_gain=True)
assert len(fine)==17 and fine[5]+256*fine[16]==131
assert len(P.voice_payload(0,**v))==16
e.source='真实 FPGA';e.send=lambda kind,payload:payload
try:e.set_voice(0,v)
except ValueError as exc:assert '旧固件' in str(exc)
else:raise AssertionError('old firmware accepted sound')
v['gate']=False;assert len(e.set_voice(0,v))==16
e.capabilities['fine_gain']=True;v['gate']=True;assert len(e.set_voice(0,v))==17
v['gain']=0;packet=e.set_voice(0,v);assert packet[5]==0 and packet[16]==0
e.close();print('PASS fine gain, legacy mute, old firmware audible-command guard, silent defaults')
