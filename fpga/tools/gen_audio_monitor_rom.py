"""Deterministic Q15 Hann/twiddles for the passive 1024-point observer."""
from pathlib import Path
import math,json,hashlib
R=Path(__file__).resolve().parents[2];W=R/'fpga/audio_monitor'
def q15(v):return max(-32768,min(32767,round(v*32768)))
def main():
 d=W/'rtl';d.mkdir(parents=True,exist_ok=True)
 t=[((q15(math.cos(2*math.pi*k/1024))&65535)<<16)|(q15(-math.sin(2*math.pi*k/1024))&65535) for k in range(512)]
 h=[q15(0.5-0.5*math.cos(2*math.pi*k/1023))&65535 for k in range(1024)]
 for name,values,width in [('fft_twiddle.hex',t,8),('fft_hann.hex',h,4)]:
  (d/name).write_text(''.join(f'{v:0{width}x}\n' for v in values),encoding='ascii')
 data={'fft_size':1024,'sample_hz':48000,'bin_hz':46.875,'window':'symmetric Hann, n/(N-1)',
       'twiddle':'cos(2*pi*k/N) - i*sin(2*pi*k/N), signed Q1.15',
       'rounding':'Python round to nearest ties-even; clamp [-32768,32767]',
       'source':'Analytic trigonometric coefficients generated locally; no copied IP',
       'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in d.glob('*.hex')}}
 (W/'coefficients.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
 print('Generated',len(t),'twiddles and',len(h),'Hann coefficients')
if __name__=='__main__':main()
