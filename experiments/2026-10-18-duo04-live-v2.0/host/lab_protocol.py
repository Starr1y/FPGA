"""TangLab v1 wire format. All multibyte integers little endian."""
import binascii
import struct
import time
from dataclasses import dataclass

MAGIC=b'\xa5\x5a'
HEADER=struct.Struct('<BBHHI')
MAX_PAYLOAD=4096
HELLO,VOICE,CAPTURE,MODE,IMU_TX,PING,PREVIEW=1,16,17,18,19,20,21
PIANO_CONFIG=22

def piano_payload(channel,hold,decay_s,fs=48000):
    import math
    if type(channel) is not int or channel not in range(4) or type(hold) is not bool:raise ValueError('钢琴声部/保持设置无效')
    if not isinstance(decay_s,(int,float)) or not math.isfinite(decay_s) or not .2<=decay_s<=30:raise ValueError('钢琴衰减时间范围0.2～30秒')
    coefficient=max(1,min(4096,round(-math.expm1(math.log(.1)/(decay_s*fs))*2**24)))
    return struct.pack('<BBH',channel,hold,coefficient)
INFO,ACK,AUDIO,ENVELOPE,IMU,STATUS,PONG=128,129,130,131,132,133,134

def crc16(data,crc=0xffff):
    return binascii.crc_hqx(data, crc)

def pack(kind,payload=b'',seq=0,tick=0):
    if len(payload)>MAX_PAYLOAD: raise ValueError('报文过长')
    body=HEADER.pack(1,kind,len(payload),seq,tick)+payload
    return MAGIC+body+struct.pack('<H',crc16(body))

@dataclass
class Frame:
    kind:int
    seq:int
    tick:int
    payload:bytes

class Parser:
    def __init__(self):
        self.buf=bytearray();self.errors=0;self.discarded=0;self.last_feed=0
    def feed(self,data,now=None):
        now=time.monotonic() if now is None else now
        if self.buf and self.last_feed and now-self.last_feed>1:
            self.buf.clear();self.errors+=1
        self.last_feed=now;self.buf.extend(data);out=[]
        while len(self.buf)>=2:
            pos=self.buf.find(MAGIC)
            if pos<0:
                keep=1 if self.buf[-1]==0xa5 else 0
                self.discarded+=len(self.buf)-keep
                self.buf[:]=self.buf[-1:] if keep else b'';break
            if pos: self.discarded+=pos;del self.buf[:pos]
            if len(self.buf)<12:break
            ver,kind,n,seq,tick=HEADER.unpack_from(self.buf,2)
            if ver!=1 or n>MAX_PAYLOAD:
                self.errors+=1;del self.buf[0];continue
            size=14+n
            if len(self.buf)<size:break
            if crc16(self.buf[2:12+n])!=struct.unpack_from('<H',self.buf,12+n)[0]:
                self.errors+=1;del self.buf[0];continue
            out.append(Frame(kind,seq,tick,bytes(self.buf[12:12+n])));del self.buf[:size]
        return out

def voice_payload(index,hz,gain,wave,gate,attack,decay,sustain,release,fs=48000,fine_gain=False):
    if not 0<=index<4 or not 0<hz<fs/2:raise ValueError('声部或频率超限')
    if wave not in range(5):raise ValueError('音色编号必须为0～4')
    def step(ms):return max(1,min(65535,round(65535/max(1,ms*fs/1000))))
    level=round(gain*(65535 if fine_gain else 255))
    packet=struct.pack('<BIBBBHHHH',index,round(hz/fs*2**32),level&255,wave,gate,
                       step(attack),step(decay),round(sustain*65535),step(release))
    return packet+bytes([level>>8]) if fine_gain else packet

def summary(values):
    if not values:return {'n':0}
    v=sorted(values)
    return dict(n=len(v),min=v[0],median=v[(len(v)-1)//2],p95=v[min(len(v)-1,int(.95*(len(v)-1)))],max=v[-1])
