"""Digital-only DUO04 regression; never invokes synthesis or Programmer."""
from pathlib import Path
import subprocess,sys,shutil,json
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'fpga/duo04'
OUT=Path(sys.argv[1]);OUT.mkdir(parents=True,exist_ok=True)
(OUT/'rtl').mkdir(exist_ok=True)
for f in (PROJECT/'rtl').glob('*.hex'):shutil.copy2(f,OUT/'rtl'/f.name)
def run(tool,args,timeout=240):
    with (OUT/(tool+'.log')).open('w',encoding='utf-8') as log:
        result=subprocess.run(['D:/FPGA_VIVADO/2025.2/Vivado/bin/'+tool+'.bat',*map(str,args)],cwd=OUT,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
    text=(OUT/(tool+'.log')).read_text(errors='replace')
    if result.returncode:raise RuntimeError(text[-5000:])
    return text
sources=[p for p in (PROJECT/'rtl').glob('*.v') if p.name not in ('top_duo02_mouse.v','top_duo03.v','video_duo03_hdmi.v')]
run('xvlog',['-d','TANG_SIM','-i',PROJECT,'-i',PROJECT/'rtl',*sources])
run('xelab',['top_duo04','-s','duo04_topcheck','--timescale','1ns/1ps'])
print('Top static elaboration PASS (TANG_SIM excludes physical PLL/TMDS)')
for name in sys.argv[2:]:
    run('xvlog',['--sv',PROJECT/'tb'/(name+'.sv')])
    run('xelab',[name,'-s',name,'--timescale','1ns/1ps'])
    (OUT/'run.tcl').write_text('run all\nquit\n')
    text=run('xsim',[name,'-tclbatch','run.tcl'])
    if 'TB_PASS' not in text:raise RuntimeError(text[-2000:])
    shutil.copy2(OUT/'xsim.log',OUT/(name+'.log'));print(name,'PASS',flush=True)
