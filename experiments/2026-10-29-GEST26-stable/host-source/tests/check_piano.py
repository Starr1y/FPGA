"""Host compatibility and independent spectral checks of the RTL piano capture."""
import sys,json,struct
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from lab_engine import LabEngine
import lab_protocol as P

e=LabEngine();e.source='真实 FPGA';e.send=lambda kind,payload:payload
v=dict(e.voices[0],wave=4,gate=True)
for version,allowed in [('1.1',False),('1.2',True)]:
    e.frame(P.Frame(P.INFO,1,0,struct.pack('<HIIBH',0,50000000,48000,4,2048)+('TangLab '+version).encode()))
    assert e.capabilities['fine_gain']
    try:packet=e.set_voice(0,v)
    except ValueError:assert not allowed
    else:assert allowed and len(packet)==17 and packet[6]==4
e.demo();e.set_voice(0,dict(v,sustain=0));assert np.any(e.audio[:,0])
e.close()
if len(sys.argv)>1:
    path=Path(sys.argv[1]);a=np.loadtxt(path/'piano.csv',delimiter=',')
    assert a.shape==(96000,5) and np.array_equal(a[:,:4].sum(axis=1),a[:,4])
    def amplitudes(data):return np.abs(np.fft.rfft(data*np.hanning(len(data))))
    peaks=[];drops=[];brightness=[]
    for ch in range(4):
        early=a[256:4352,ch];late=a[80000:84096,ch];freq=375*(ch+1)
        f=np.fft.rfftfreq(len(early),1/48000);x=amplitudes(early);y=amplitudes(late)
        peak=float(f[np.argmax(x)]);assert abs(peak-freq)<12;peaks.append(peak)
        b=int(np.argmin(abs(f-freq)));h=int(np.argmin(abs(f-2*freq)))
        assert x[h]/x[b]>.05 and y[h]/y[b]<.02
        ratio=float(np.sqrt(np.mean(late**2)/np.mean(early**2)));assert .45<ratio<.7
        drops.append(ratio);brightness.append(float(x[h]/x[b]))
    (path/'validation.json').write_text(json.dumps(dict(result='PASS',fundamentals_hz=peaks,late_early_rms=drops,early_second_harmonic=brightness),indent=2))
print('PASS piano firmware guard, demo, and requested RTL spectrum checks')
