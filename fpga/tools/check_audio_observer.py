"""RTL vs integer and independent NumPy FFT; no hardware/serial interaction."""
from pathlib import Path
import argparse,hashlib,json,math,random,subprocess,tempfile
import numpy as np
R=Path(__file__).resolve().parents[2];W=R/'fpga/audio_monitor';O=R/'board-test/audio-monitor'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def signed(v,b):return v-(1<<b) if v&(1<<(b-1)) else v
def integer_fft(x,h,t):
 a=[(int(x[i])*h[i]>>7,0) for i in range(1024)]
 a=[a[int(f'{i:010b}'[::-1],2)] for i in range(1024)]
 for stage in range(10):
  size=1<<(stage+1);half=size>>1
  for base in range(0,1024,size):
   for j in range(half):
    ar,ai=a[base+j];br,bi=a[base+j+half];wr,wi=t[j*(1024//size)]
    tr=br if j==0 else (br*wr-bi*wi)>>15;ti=bi if j==0 else (br*wi+bi*wr)>>15
    plus=((ar+tr)>>1,(ai+ti)>>1);minus=((ar-tr)>>1,(ai-ti)>>1)
    assert all(-(1<<23)<=v<(1<<23) for v in plus+minus),'internal fixed-point overflow'
    a[base+j]=plus;a[base+j+half]=minus
 return a[:513]
def vectors():
 n=np.arange(1024);rng=random.Random(6815)
 def tone(b,amp,cos=False):return np.rint(amp*(np.cos if cos else np.sin)(2*np.pi*b*n/1024)).astype(int)
 z=np.zeros(1024,dtype=int);imp=z.copy();imp[0]=32767;imp[511]=-32768
 edge=z.copy();edge[-1]=32767;edge[512]=25000
 return [(z,z),(np.full(1024,18000),np.full(1024,-22000)),(imp,edge),
         (tone(10,20000),tone(31,17000,True)),(tone(10.4,24000),tone(70.7,18000)),
         (tone(7,14000)+tone(123,8000),tone(11,12000)+tone(240,12000,True)),
         (np.where(n%2==0,32767,-32768),np.where(n<512,-32768,32767)),
         (np.array([rng.randrange(-32768,32768) for _ in n]),np.array([rng.randrange(-32768,32768) for _ in n])),
         (np.full(1024,-32768),np.full(1024,32767))]
def verify():
 d=json.loads((O/'validation.json').read_text(encoding='utf8'));assert d['passed']
 for n,h in d['source_sha256'].items():assert sha(R/n)==h,n
 for n,h in d['evidence_sha256'].items():assert sha(O/n)==h,n
 print('PASS passive audio observer source and numeric evidence; no board proof')
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=list((W/'rtl').glob('*'))+[W/'coefficients.json',W/'tb/tb_stereo_fft_observer.sv',Path(__file__),R/'fpga/tools/gen_audio_monitor_rom.py']
 before={p.relative_to(R).as_posix():sha(p) for p in files if p.is_file()}
 h=[int(s,16) for s in (W/'rtl/fft_hann.hex').read_text().split()]
 t=[(signed(int(s,16)>>16,16),signed(int(s,16)&65535,16)) for s in (W/'rtl/fft_twiddle.hex').read_text().split()]
 expected_h=np.rint((.5-.5*np.cos(2*np.pi*np.arange(1024)/1023))*32768).clip(-32768,32767).astype(int)
 assert h==expected_h.tolist() and h[0]==h[-1]==0
 for k,(wr,wi) in enumerate(t):
  assert wr==max(-32768,min(32767,round(math.cos(2*math.pi*k/1024)*32768)))
  assert wi==max(-32768,min(32767,round(-math.sin(2*math.pi*k/1024)*32768)))
 cases=vectors();data=O/'input.hex';data.write_text(''.join(f'{((int(r)&65535)<<16)|(int(l)&65535):08x}\n' for left,right in cases for l,r in zip(left,right)),encoding='ascii')
 output=O/'numeric.txt';compiled=O/'observer.vvp'
 cmd='cd '+q(linux(W))+' && iverilog -g2012 -s tb_stereo_fft_observer -o '+q(linux(compiled))+' rtl/stereo_fft_observer.v tb/tb_stereo_fft_observer.sv && vvp '+q(linux(compiled))+' '+q('+DATA='+linux(data))+' '+q('+RESULT='+linux(output))
 a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
 log=a.stdout.decode('utf8',errors='replace')+'\n'+a.stderr.decode('utf8',errors='replace');(O/'observer.log').write_text(log,encoding='utf8')
 assert a.returncode==0 and 'TB_PASS' in log,log[-3000:]
 starts={};bins={};waves={};done={}
 for line in output.read_text().splitlines():
  tag,*v=line.split();v=[int(x) for x in v];key=tuple(v[:2])
  if tag=='S':assert key not in starts;starts[key]=True
  elif tag=='D':assert key not in done;done[key]=v[2:]
  elif tag in ('B','W'):
   dest=bins if tag=='B' else waves;k=tuple(v[:4]);assert k not in dest,(tag,k);dest[k]=tuple(v[4:])
 assert set(done)=={(1,i) for i in range(9)}|{(2,0),(2,6),(4,0)}
 errors=[];peaks=[];checked_bins=0;checked_columns=0
 for phase,frame in sorted(done):
  vector=frame if phase==1 else 0 if (phase,frame)==(2,0) else 7 if phase==2 else 4
  drops,count,cycles=done[(phase,frame)];assert cycles<200000
  if phase==1:assert drops==0 and count==frame+1
  for ch,x in enumerate(cases[vector]):
   exact=integer_fft(x,h,t)
   actual=[bins[(phase,frame,ch,k)] for k in range(513)]
   assert actual==exact,('RTL/integer mismatch',phase,frame,ch,next((k for k in range(513) if actual[k]!=exact[k]),None))
   # Independent floating FFT uses the quantized input window, forward /N.
   reference=np.fft.rfft(x*np.array(h)/32768,norm='forward')*256
   av=np.array([complex(re,im) for re,im in actual]);max_error=float(np.max(np.abs(av-reference)))
   assert max_error<256,('FFT differs by >=1 PCM LSB',phase,frame,ch,max_error)
   errors.append(max_error);peak=int(np.argmax(np.abs(av[1:]))+1)
   peaks.append({'phase':phase,'frame':frame,'channel':ch,'peak_bin_excluding_dc':peak,'max_complex_error_q8':max_error})
   for col in range(64):
    segment=x[col*16:col*16+16];assert waves[(phase,frame,ch,col)]==(int(min(segment)),int(max(segment)))
    checked_columns+=1
   checked_bins+=513
 aborted_bins=sum(k[0]==3 for k in bins);aborted_waves=sum(k[0]==3 for k in waves)
 assert len(bins)==checked_bins+aborted_bins and len(waves)==checked_columns+aborted_waves
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files if p.is_file()},'source changed'
 d={'passed':True,'source_sha256':before,'evidence_sha256':{p.name:sha(p) for p in (data,output,O/'observer.log')},
    'clock_hz':50000000,'native_pcm_hz':48000,'fft_size':1024,'bin_hz_nominal':46.875,
    'native_stereo_frames':9,'all_completed_frames':12,'complex_bins_checked':checked_bins,'wave_columns_checked':checked_columns,
    'integer_bit_exact':True,'independent_reference':'NumPy rfft, norm=forward, quantized symmetric Hann window',
    'numpy_version':np.__version__,'max_complex_error_q8':max(errors),'per_channel':peaks,
    'cycles_per_stereo_frame':max(v[2] for v in done.values()),'overload_and_reset_checked':True,
    'reset_aborted_partial_bins':aborted_bins,'reset_aborted_partial_wave_columns':aborted_waves,
    'physical_tested':False,'integrated_into_board_top':False,'hdmi_rendered':False,'timing_verified':False}
 (O/'validation.json').write_text(json.dumps(d,indent=2)+'\n',encoding='utf8')
 print(log.split('TB_PASS')[-1].splitlines()[0],flush=True)
 print(json.dumps({k:d[k] for k in ('complex_bins_checked','wave_columns_checked','max_complex_error_q8','cycles_per_stereo_frame')},indent=2),flush=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--verify',action='store_true');a=p.parse_args();verify() if a.verify else main()
