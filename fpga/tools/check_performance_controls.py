"""Standalone mechanical input logic checks; no pin assignment or download."""
from pathlib import Path
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[2];W=R/'fpga/controls';O=R/'board-test/controls'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def main():
 O.mkdir(parents=True,exist_ok=True);files=list((W/'rtl').glob('*.v'))+list((W/'tb').glob('*.sv'))
 before={p.relative_to(R).as_posix():sha(p) for p in files};tests={}
 for name,top,flags in [('2','tb_performance_controls','-P tb_performance_controls.EDGES=2'),('4','tb_performance_controls','-P tb_performance_controls.EDGES=4'),('menu','tb_instrument_menu','')]:
  cmd='cd '+q(linux(W))+' && iverilog -g2012 -s '+top+' '+flags+' -o '+q(linux(O/f'controls-{name}.vvp'))+' '+' '.join(q(linux(p)) for p in files)+' && vvp '+q(linux(O/f'controls-{name}.vvp'))
  a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
  output=a.stdout.decode('utf8',errors='replace');(O/f'controls-{name}.log').write_text(output+'\n'+a.stderr.decode('utf8',errors='replace'),encoding='utf8')
  tests[name]={'passed':a.returncode==0 and 'TB_PASS' in output,'messages':[s for s in output.splitlines() if 'TB_PASS' in s or 'FATAL' in s]}
  print(tests[name],flush=True)
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'source changed'
 data={'passed':all(t['passed'] for t in tests.values()),'source_sha256':before,'tests':tests,
  'test_ms_enable_hz':1000,'test_debounce_ms':3,'integrated_into_board_top':False,'physical_controls_verified':False}
 (O/'validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
 raise SystemExit(0 if data['passed'] else 1)
if __name__=='__main__':main()
