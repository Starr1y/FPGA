"""Summarize actual XSim PCM and decode real-bit simulated UART with host parser."""
from pathlib import Path
import sys,json,wave
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from lab_protocol import Parser
from lab_engine import LabEngine
audio,wire,out=map(Path,sys.argv[1:4]);out.mkdir(parents=True,exist_ok=True)
data=np.genfromtxt(audio,delimiter=',',names=True,dtype=None,encoding='utf-8')
names=['钢琴','马林巴','电钢琴','拨弦'];rows=[]
for kind in range(4):
    for note in (36,48,60):
        for velocity in (48,96):
            x=data['value'][(data['kind']==kind)&(data['note']==note)&(data['velocity']==velocity)].astype(float)
            assert len(x)>=8192
            f0=440*2**((note-69)/12);spec=abs(np.fft.rfft((x-x.mean())*np.hanning(len(x)),262144))
            freq=np.fft.rfftfreq(262144,1/48000);mask=(freq>f0*.97)&(freq<f0*1.03)
            estimate=freq[mask][np.argmax(spec[mask])];cents=1200*np.log2(estimate/f0)
            assert abs(cents)<15 and max(abs(x))<32767,(kind,note,velocity,cents)
            rows.append(dict(timbre=names[kind],midi=note,velocity=velocity,samples=len(x),peak=int(max(abs(x))),rms=float(np.sqrt(np.mean(x*x))),estimated_hz=float(estimate),fft_estimated_cents=float(cents)))
            if note==60 and velocity==96:
                z=x-x.mean();z*=32767*10**(-24/20)/np.sqrt(np.mean(z*z))
                with wave.open(str(out/(names[kind]+'-C4-RTL试听.wav')),'wb') as f:
                    f.setparams((1,2,48000,0,'NONE','not compressed'));f.writeframes(np.round(z).astype('<i2').tobytes())
parser=Parser();frames=parser.feed(bytes.fromhex(wire.read_text()))
assert parser.errors==0 and parser.discarded==0
engine=LabEngine()
for f in frames:engine.frame(f)
assert engine.ready and engine.device.startswith('DUO04-LIVE')
assert engine.audio.shape==(512,5) and engine.voice_audio.shape==(512,4)
result=dict(result='PASS',source='RTL simulation, not physical audio',pitch_method='Finite-window FFT near expected fundamental; not precision frequency counter',rows=rows,uart_frames=len(frames),crc_errors=parser.errors,capture_shape=list(engine.audio.shape),monitor_shape=list(engine.voice_audio.shape))
(out/'metrics.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS 24 timbre/note/velocity cases, UART CRC and five+four channel capture')
