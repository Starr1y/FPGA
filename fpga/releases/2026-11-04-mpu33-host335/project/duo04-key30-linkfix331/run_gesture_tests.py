"""Run named XSim testbenches; XSim must be available on PATH. No EDA implementation or programming."""
from pathlib import Path
import subprocess,xml.etree.ElementTree as ET,shutil,sys,os
r=Path(__file__).resolve().parent;out=Path(os.environ.get('TANGLAB_SIM_WORK',str(r/'validation/xsim-work')));out.mkdir(parents=True,exist_ok=True)
(out/'rtl').mkdir(exist_ok=True);(out/'preview').mkdir(exist_ok=True)
for p in (r/'rtl').iterdir():
 if p.suffix in ('.hex','.vh'):shutil.copy2(p,out/'rtl'/p.name)
files=[str(r/f.get('path')) for f in ET.parse(r/'tanglab_duo04_key30_linkfix331.gprj').iter('File') if f.get('type')=='file.verilog']
def run(args,name,timeout=180):
 p=subprocess.run(args,cwd=out,capture_output=True,text=True,errors='replace',timeout=timeout)
 (out/(name+'.log')).write_text(p.stdout+p.stderr,encoding='utf8');print(name,p.returncode,(p.stdout+p.stderr)[-1500:],flush=True)
 if p.returncode:raise SystemExit(p.returncode)
 return p.stdout+p.stderr
tests=sys.argv[1:] or ['tb_keys30','tb_expression30','tb_range30','tb_lite_legato','tb_lite_chord','tb_mpu_buttons30','tb_duo04_32','tb_score27_uart','tb_duo04_panel']
defines=[] if tests==['tb_pixel_reset'] else ['-d','TANG_SIM']
run(['xvlog.bat',*defines,'-i',str(r),*files,'--sv',*[str(r/'tb'/f'{t}.sv') for t in tests]],'compile')
for t in tests:
 run(['xelab.bat',t,'-s',t+'_sim','-debug','typical','-timescale','1ns/1ps'],t+'-elaborate')
 log=run(['xsim.bat',t+'_sim','-runall'],t,600)
 if 'TB_PASS' not in log:raise SystemExit('Missing PASS '+t)

