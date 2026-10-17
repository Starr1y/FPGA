"""DUO03 functional checks. No board download, no bitstream completion claim."""
from pathlib import Path
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo03';O=R/'board-test/duo03'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def run(top,files):
 inputs=files+list((W/'rtl').glob('*.hex'))+list((W/'rtl').glob('*.vh'))
 before={p.relative_to(R).as_posix():sha(p) for p in inputs}
 cmd='cd '+q(linux(W))+' && iverilog -g2012 -DTANG_SIM -s '+top+' -o '+q(linux(O/(top+'.vvp')))+' '+' '.join(q(linux(p)) for p in files)+' && stdbuf -oL vvp '+q(linux(O/(top+'.vvp')))+' +OUT='+q(linux(O))
 a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True);text=(a.stdout+a.stderr).decode('utf8',errors='replace')
 (O/(top+'.log')).write_text(text,encoding='utf8');assert a.returncode==0 and 'TB_PASS' in text and 'ERROR:' not in text,text
 assert before=={p.relative_to(R).as_posix():sha(p) for p in inputs},'source changed during check'
 data={'passed':True,'source_sha256':before,'messages':[s for s in text.splitlines() if 'TB_PASS' in s],
  'physical_board_tested':False,'simulation_only':True}
 (O/(top+'-validation.json')).write_text(json.dumps(data,indent=2)+'\n',encoding='utf8');print(data['messages'],flush=True)
if __name__=='__main__':
 O.mkdir(parents=True,exist_ok=True)
 run('tb_duo_controls',[W/'rtl'/n for n in ('duo_key_events.v','duo_controls.v','duo_parameters.v','performance_controls.v','release_button.v')]+[W/'tb/tb_duo_controls.sv'])
