"""Targeted new piano and limiter checks; no physical listening claims."""
from pathlib import Path
import sys,subprocess,shutil,json
import numpy as np
root=Path(__file__).resolve().parents[1];p=root/'fpga/duo02-mouse';out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False);(out/'rtl').mkdir()
for f in (p/'rtl').glob('*.hex'):shutil.copy2(f,out/'rtl'/f.name)
def run(tool,args,label):
    with (out/(label+'.log')).open('w') as log:
        q=subprocess.run([f'D:/FPGA_VIVADO/2025.2/Vivado/bin/{tool}.bat',*map(str,args)],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=360)
    text=(out/(label+'.log')).read_text(errors='replace');assert q.returncode==0,text[-1600:];return text
names=['dual_note_map','dual_voice_scheduler','dual_audio_core','two_hand_synth','timbre_presets','sine_lut','instrument_waves','fm_limits','stereo_makeup_limiter']
run('xvlog',['--sv',*[p/'rtl'/(x+'.v') for x in names],p/'tb/tb_audio_quality.sv',p/'tb/tb_makeup_limiter.sv'],'compile')
(out/'run.tcl').write_text('run all\nquit\n')
for name in ['tb_makeup_limiter','tb_audio_quality']:
    run('xelab',[name,'-s',name,'--timescale','1ns/1ps'],name+'-elab')
    text=run('xsim',[name,'-tclbatch','run.tcl'],name)
    assert 'TB_PASS' in text,text[-1800:]
data=np.genfromtxt(out/'quality.csv',delimiter=',',names=True,dtype=None,encoding='utf-8')
decay=data[data['mode']=='decay'];held=data[data['mode']=='hold'];lut=data[data['mode']=='lut']
assert len(decay)==9600 and len(held)==12000
assert np.max(np.abs(decay['left']))>3000 and np.all(decay['right']==0)
assert np.max(np.abs(held['left'][-2048:]))>3000
assert np.all(lut['left']==np.rint(32767*np.sin(2*np.pi*lut['sample']/1024)))
phase=(np.arange(65536)+.5)/65536*2*np.pi;reference=np.sin(phase)
snr={}
for points in [256,1024]:
    quantized=np.sin(np.floor(phase/(2*np.pi)*points)*2*np.pi/points)
    snr[points]=float(10*np.log10(np.mean(reference**2)/np.mean((reference-quantized)**2)))
assert snr[1024]-snr[256]>11
result=dict(result='PASS',basis='RTL simulation, not physical sound quality',piano_t10_s=.2,hold_checked_s=.25,
            phase_quantization_snr_db=snr,limiter_ceiling=28000,makeup_db=18.06)
(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
