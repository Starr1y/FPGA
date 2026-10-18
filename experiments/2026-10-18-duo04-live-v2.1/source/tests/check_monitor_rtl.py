from pathlib import Path
import sys,subprocess,json,numpy as np
root=Path(__file__).resolve().parents[1];p=root/'fpga/duo02-mouse';out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False)
def run(tool,args):
 with (out/(tool+'.log')).open('w') as log:q=subprocess.run([f'D:/FPGA_VIVADO/2025.2/Vivado/bin/{tool}.bat',*map(str,args)],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=180)
 text=(out/(tool+'.log')).read_text(errors='replace');assert q.returncode==0,text[-1200:];return text
run('xvlog',['--sv',p/'rtl/sine_lut.v',p/'rtl/sine_calibrator.v',p/'tb/tb_sine_calibrator.sv']);run('xelab',['tb_sine_calibrator','-s','sine','--timescale','1ns/1ps'])
(out/'run.tcl').write_text('run all\nquit\n');assert 'TB_PASS' in run('xsim',['sine','-tclbatch','run.tcl'])
a=np.genfromtxt(out/'sine.csv',delimiter=',',skip_header=1);wave=a[1000:49000,1];peak=np.max(abs(wave));rms=np.sqrt(np.mean(wave**2));hz=np.fft.rfftfreq(len(wave),1/48000)[np.argmax(abs(np.fft.rfft(wave)))];level=20*np.log10(peak/32767)
assert hz==1000 and abs(level+30)<.02 and abs(rms-1036/2**.5)<2
assert np.array_equal(a[:300000,1],a[:300000,2]);assert np.max(abs(a[295000:300000,1]))>1000
assert np.all(a[300260:300270,1:3]==0)
r=dict(result='PASS',basis='RTL accelerated sample enable, not physical',frequency_hz=hz,level_dbfs=level,rms_pcm=rms,persistent_nominal_seconds=6.25,ramp_samples=256,ramp_ms=256/48)
(out/'result.json').write_text(json.dumps(r,indent=2));print(r)
