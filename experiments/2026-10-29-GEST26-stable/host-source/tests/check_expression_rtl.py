from pathlib import Path
import sys,subprocess,shutil,json,numpy as np
root=Path(__file__).resolve().parents[1];p=root/'fpga/duo02-mouse';out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False);(out/'rtl').mkdir()
for f in (p/'rtl').glob('*.hex'):shutil.copy2(f,out/'rtl'/f.name)
def run(tool,args):
 with (out/(tool+'.log')).open('w') as log:r=subprocess.run([f'D:/FPGA_VIVADO/2025.2/Vivado/bin/{tool}.bat',*map(str,args)],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=240)
 text=(out/(tool+'.log')).read_text(errors='replace');assert r.returncode==0,text[-1600:];print(tool,r.returncode,flush=True);return text
names=['sine_lut','instrument_waves','fm_limits','dual_audio_core','performance_vibrato']
run('xvlog',['--sv',*[p/'rtl'/(n+'.v') for n in names],p/'tb/tb_expression_quality.sv',p/'rtl/stereo_makeup_limiter.v',p/'tb/tb_makeup_limiter.sv'])
run('xelab',['tb_expression_quality','-s','quality','--timescale','1ns/1ps']);(out/'run.tcl').write_text('run all\nquit\n');text=run('xsim',['quality','-tclbatch','run.tcl']);assert 'TB_PASS' in text,text[-1800:]
a=np.genfromtxt(out/'expression.csv',delimiter=',',names=True,dtype=None,encoding='utf-8');harmonics={}
for midi in (36,48,60):
 d=a[np.char.replace(a['mode'],' ','')==f'piano{midi}']
 assert len(d)==4096,(midi,a['mode'][:1]);f=440*2**((midi-69)/12);t=np.arange(len(d))/48000
 basis=np.column_stack([func(2*np.pi*k*f*t) for k in range(1,5) for func in (np.sin,np.cos)])
 b=np.linalg.lstsq(basis,d['value'],rcond=None)[0];amps=np.hypot(b[::2],b[1::2]);db=20*np.log10(np.maximum(amps/amps[0],1e-9));assert -23<db[1]<-17,db
 harmonics[str(midi)]=db.tolist()
g=a[np.char.strip(a['mode'])=='glide'];x=g['value'];assert np.all(np.diff(x)>=0) and x[-1]==g['freq'][-1]
arrival=int(g['index'][np.flatnonzero(x==g['freq'])[0]]);assert 9500<arrival<9700
v=a[np.char.strip(a['mode'])=='vibrato'];cents=1200*np.log2(v['ratio']/65536);assert -42<cents.min()<-38 and 38<cents.max()<42
phase=v['value'].astype(np.int64);delta=np.diff(phase);delta[delta<0]+=2**32;actual=1200*np.log2(delta/(16*v['freq'][1:]));assert -42<actual.min()<-38 and 38<actual.max()<42
r=dict(result='PASS',basis='RTL accelerated sample enable; not physical listening',piano_harmonics_db=harmonics,glide_arrival_ms=arrival/48,vibrato_cents=[float(cents.min()),float(cents.max())],synthesis='NOT RUN',board='NOT RUN')
run('xelab',['tb_makeup_limiter','-s','limiter','--timescale','1ns/1ps']);assert 'TB_PASS' in run('xsim',['limiter','-tclbatch','run.tcl'])
(out/'result.json').write_text(json.dumps(r,indent=2));print(r)
