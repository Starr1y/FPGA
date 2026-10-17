"""Production clock digital board adapter check. No hardware download."""
from pathlib import Path
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo03';O=R/'board-test/duo03'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=sorted(p for p in (W/'rtl').glob('*.v') if p.name!='video_pll_125.v')+[W/'tb/tb_duo03_board.sv',R/'fpga/dualhand/tb/bno_two_hand_peer.sv']
 before={p.relative_to(R).as_posix():sha(p) for p in files+list((W/'rtl').glob('*.hex'))}
 output=O/'tb_duo03_board.vvp';cmd='cd '+q(linux(W))+' && iverilog -g2012 -DTANG_SIM -s tb_duo03_board -o '+q(linux(output))+' '+' '.join(q(linux(p)) for p in files)+' && stdbuf -oL vvp '+q(linux(output))
 with (O/'board-path.log').open('wb') as log:r=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],stdout=log,stderr=subprocess.STDOUT)
 text=(O/'board-path.log').read_bytes().decode('utf8',errors='replace');passed=r.returncode==0 and 'TB_PASS' in text
 assert before=={n:sha(R/n) for n in before},'inputs changed during board check'
 data={'passed':passed,'source_sha256':before,'clock_hz':50000000,'sample_hz':48000,'report_hz':100,
  'boot_reset_waits_shortened':True,'note_hold_test_override_ms':400,'control_stimulus':'forced canonical parameter outputs; raw input semantics and control-to-RGB checked separately',
  'tmds_primitives_simulated':False,'physical_board_tested':False,'messages':[s for s in text.splitlines() if 'TB_PASS' in s or 'FATAL' in s]}
 (O/'board-path-validation.json').write_text(json.dumps(data,indent=2)+'\n');print(data['messages'],flush=True)
 raise SystemExit(0 if passed else 1)
if __name__=='__main__':main()
