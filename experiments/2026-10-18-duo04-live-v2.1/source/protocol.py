"""Bounded UART decoders. No GUI/serial dependencies; units: SI, radians internally."""
import math
import struct
from dataclasses import dataclass, field

REPORTS = {1: ('accel', 10, 8), 2: ('gyro', 10, 9),
           4: ('linear', 10, 8), 5: ('rotation', 14, 14),
           8: ('game', 12, 14), 0x28: ('stabilized', 14, 14)}
POSE_IDS = (5, 8, 0x28)

def normalize(q):
    n = math.sqrt(sum(x*x for x in q))
    if n < 1e-9 or not math.isfinite(n):
        raise ValueError('无效四元数')
    return tuple(x/n for x in q)

def multiply(a, b):
    x,y,z,w = a; X,Y,Z,W = b
    return (w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
            w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z)

def relative(q, origin):
    return normalize(multiply((-origin[0],-origin[1],-origin[2],origin[3]), q))

def from_euler(yaw, pitch, roll):
    y,p,r = [math.radians(v)/2 for v in (yaw,pitch,roll)]
    cy,sy,cp,sp,cr,sr=math.cos(y),math.sin(y),math.cos(p),math.sin(p),math.cos(r),math.sin(r)
    return (sr*cp*cy-cr*sp*sy, cr*sp*cy+sr*cp*sy, cr*cp*sy-sr*sp*cy, cr*cp*cy+sr*sp*sy)

def euler(q):
    x,y,z,w=normalize(q)
    return tuple(map(math.degrees, (math.atan2(2*(w*z+x*y),1-2*(y*y+z*z)),
         math.asin(max(-1,min(1,2*(w*y-z*x)))), math.atan2(2*(w*x+y*z),1-2*(x*x+y*y)))))

def rotation_matrix(q):
    x,y,z,w=normalize(q)
    return ((1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)),
            (2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)),
            (2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)))

@dataclass
class Sample:
    kind: str
    values: tuple
    seq: int
    accuracy: int | None = None
    sensor_offset_us: int | None = None

class RVCParser:
    def __init__(self):
        self.buf=bytearray(); self.errors=0; self.discarded=0
    def feed(self, data):
        self.buf.extend(data); out=[]
        while len(self.buf)>=2:
            k=self.buf.find(b'\xaa\xaa')
            if k<0:
                keep=1 if self.buf[-1]==0xaa else 0
                self.discarded+=len(self.buf)-keep
                self.buf[:]=self.buf[-1:] if keep else b''
                break
            if k:
                self.discarded+=k; del self.buf[:k]
            if len(self.buf)<19: break
            f=self.buf[:19]
            if (sum(f[2:18])&255)!=f[18]:
                self.errors+=1; del self.buf[0]; continue
            seq=f[2]; vals=struct.unpack_from('<6h',f,3)
            out.append(Sample('rvc',tuple(v/100 for v in vals[:3])+tuple(v*.00980665 for v in vals[3:]),seq))
            del self.buf[:19]
        return out

def encode_packet(channel, sequence, payload):
    raw=struct.pack('<HBB',len(payload)+4,channel,sequence)+payload
    out=bytearray(b'\x7e\x01')
    for b in raw:
        if b in (0x7e,0x7d): out.extend((0x7d,b^0x20))
        else: out.append(b)
    out.append(0x7e)
    return bytes(out)

class SHTPParser:
    def __init__(self):
        self.buf=bytearray(); self.active=False; self.escape=False; self.errors=0
        self.discarded=0; self.seq={}; self.sequence_gaps=0; self.controls=0
    def feed(self,data):
        out=[]
        for b in data:
            if b==0x7e:
                if self.active and self.buf:
                    if self.escape: self.errors+=1
                    elif self.buf[0]==1:
                        raw=bytes(self.buf[1:])
                        if len(raw)>=4:
                            length,ch,seq=struct.unpack_from('<HBB',raw)
                            # UART carries a complete SHTP cargo; fragmented transfers are rejected explicitly.
                            if length&0x8000 or length!=len(raw) or ch>5:
                                self.errors+=1
                            else:
                                old=self.seq.get(ch)
                                if old is not None and seq!=(old+1)&255: self.sequence_gaps+=1
                                self.seq[ch]=seq; out.append((ch,seq,raw[4:]))
                        else: self.errors+=1
                    else: self.controls+=1
                self.active=True; self.buf.clear(); self.escape=False
            elif self.active:
                if self.escape: self.buf.append(b^0x20); self.escape=False
                elif b==0x7d: self.escape=True
                else: self.buf.append(b)
                if len(self.buf)>32768:
                    self.errors+=1; self.active=False; self.buf.clear(); self.escape=False
            else: self.discarded+=1
        return out
    def expire(self):
        if self.buf:
            self.errors+=1; self.buf.clear(); self.escape=False; self.active=False

def decode_reports(payload):
    """Return reports and count unsupported/truncated cargo. Offset is relative, NOT a clock."""
    out=[]; i=0; base=None
    while i<len(payload):
        rid=payload[i]
        if rid in (0xfb,0xfa):
            if i+5>len(payload): return out,1
            ticks=struct.unpack_from('<i',payload,i+1)[0]
            base=-ticks if rid==0xfb else ((base if base is not None else 0)+ticks)
            i+=5; continue
        if rid not in REPORTS: return out,1
        kind,size,q=REPORTS[rid]
        if i+size>len(payload): return out,1
        seq,status,delay=payload[i+1:i+4]
        offset=None if base is None else (base+(((status&0xfc)<<6)|delay))*100
        n=4 if rid in POSE_IDS else 3
        vals=tuple(v/(1<<q) for v in struct.unpack_from('<'+'h'*n,payload,i+4))
        if n==4:
            try: vals=normalize(vals)
            except ValueError: return out,1
        out.append(Sample(kind,vals,seq,status&3,offset)); i+=size
    return out,0

def set_feature(report_id, hz):
    interval=round(1_000_000/hz) if hz else 0
    return struct.pack('<BBBHIII',0xfd,report_id,0,0,interval,0,0)

def feature_response(payload):
    if len(payload)<17 or payload[0]!=0xfc: return None
    return payload[1],struct.unpack_from('<I',payload,5)[0]

class ConfigTracker:
    def __init__(self): self.pending={}; self.confirmed={}; self.failures={}
    def request(self,rid,hz,now):
        self.pending[rid]=(round(1e6/hz) if hz else 0,now+5)
        self.confirmed.pop(rid,None); self.failures.pop(rid,None)
    def response(self,rid,interval):
        self.confirmed[rid]=interval
        if rid in self.pending:
            requested,_=self.pending[rid]
            if (requested==0)!=(interval==0):
                self.failures[rid]='启用/停用状态不匹配'
            self.pending.pop(rid)
    def expire(self,now):
        for rid,(_,deadline) in list(self.pending.items()):
            if now>deadline:
                self.pending.pop(rid); self.failures[rid]='配置无应答（超时）'
