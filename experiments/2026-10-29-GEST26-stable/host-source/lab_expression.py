"""Explicit per-hand vibrato/portamento; separate from accidental distortion."""
import math,struct
DEFAULT=dict(vibrato=False,vibrato_hz=5.5,vibrato_cents=20,glide=False,glide_ms=150)
def expression_payload(params):
 if set(params)-{'hands'}:raise ValueError('未知演奏表情参数')
 hands=params.get('hands')
 if not isinstance(hands,list) or len(hands)!=2:raise ValueError('hands必须包含左右两手的设置')
 result=[];wire=b''
 for entry in hands:
  if not isinstance(entry,dict) or set(entry)-set(DEFAULT):raise ValueError('未知颤音/滑音参数')
  d=dict(DEFAULT,**entry)
  for key in ('vibrato','glide'):
   if type(d[key]) is not bool:raise ValueError('颤音和滑音开关使用布尔值')
  for key,lo,hi in [('vibrato_hz',.1,12),('vibrato_cents',0,100),('glide_ms',10,2000)]:
   if type(d[key]) not in (int,float) or not math.isfinite(d[key]) or not lo<=d[key]<=hi:raise ValueError(f'{key}范围{lo}～{hi}')
  rate=round(d['vibrato_hz']/48000*2**32);depth=round(d['vibrato_cents']) if d['vibrato'] else 0;step=math.ceil(2**24/(48*d['glide_ms'])) if d['glide'] else 0
  wire+=struct.pack('<IB',rate,depth)+step.to_bytes(3,'little');result.append(d)
 return result,wire

def decode_expression(wire):
 hands=[]
 for h in range(2):
  rate,depth=struct.unpack_from('<IB',wire,h*8);step=int.from_bytes(wire[h*8+5:h*8+8],'little')
  hands.append(dict(vibrato=bool(depth),vibrato_hz=rate*48000/2**32 if rate else 5.5,vibrato_cents=depth,glide=bool(step),glide_ms=round(2**24/(48*step)) if step else 150))
 return hands

def execute_expression(c,j,p):
 e=c.engine
 if not e.capabilities.get('duo_expression'):raise ValueError('颤音/滑音需要DUO02-MOUSE 1.4固件，请自行重新编译下载')
 hands,wire=expression_payload(p);c.ack(j,e.send(57,wire));e.expression=hands
 return dict(accepted=True,hands=hands,source=e.source)
