from pathlib import Path
import subprocess,shutil,xml.etree.ElementTree as ET,sys,json
R=Path(__file__).resolve().parent;W=Path(sys.argv[1]).resolve()
out=W/'simulation';out.mkdir(parents=True,exist_ok=True)
(out/'rtl').mkdir(exist_ok=True)
for p in (R/'rtl').iterdir():
 if p.suffix in ('.hex','.vh'):shutil.copy2(p,out/'rtl'/p.name)
def run(args,name,timeout=180):
 p=subprocess.run(args,cwd=out,capture_output=True,text=True,errors='replace',timeout=timeout)
 (out/(name+'.log')).write_text(p.stdout+p.stderr,encoding='utf-8')
 print(name,p.returncode,(p.stdout+p.stderr)[-1800:]);assert p.returncode==0,name
 return p.stdout+p.stderr
files=[str(R/e.get('path')) for e in ET.parse(R/'tanglab_duo04.gprj').iter('File') if e.get('type')=='file.verilog']
tests=sys.argv[2:] or ['tb_ui21_controls','tb_ui21_stop','tb_ui21_encoder','tb_ui21_lesson','tb_ui21_uart','tb_ui21_panel']
run(['xvlog.bat','-d','TANG_SIM','-i',str(R),*files,'--sv',*[str(R/'tb'/f'{t}.sv') for t in tests]],'compile')
for t in tests:
 run(['xelab.bat',t,'-s',t+'_sim','-debug','typical','-timescale','1ns/1ps'],t+'-elaborate')
 log=run(['xsim.bat',t+'_sim','-runall'],t,600)
 assert 'TB_PASS' in log,t
print('REQUESTED_RTL_TESTS_PASS',tests)
