"""Production stereo FX/mute/DAC digital check; no board download."""
from pathlib import Path
import json,hashlib,subprocess
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo02';O=R/'board-test/duo02'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=[W/'rtl'/n for n in ('stereo_fx.v','stereo_output_path.v','pt8211_output.v')]+[W/'tb/tb_stereo_output_path.sv']
 before={p.relative_to(R).as_posix():sha(p) for p in files}
 cmd='cd '+q(linux(W))+' && iverilog -g2012 -s tb_stereo_output_path -o '+q(linux(O/'stereo-output.vvp'))+' '+' '.join(q(linux(p)) for p in files)+' && stdbuf -oL vvp '+q(linux(O/'stereo-output.vvp'))
 with (O/'stereo-output.log').open('wb') as log:a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],stdout=log,stderr=subprocess.STDOUT)
 output=(O/'stereo-output.log').read_text(encoding='utf8',errors='replace')
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'inputs changed'
 data={'passed':a.returncode==0 and 'TB_PASS' in output,'source_sha256':before,'clock_hz':50000000,'sample_hz':48000,
  'ring_samples_per_channel':16384,'physical_audio_tested':False,'messages':[s for s in output.splitlines() if 'TB_PASS' in s or 'FATAL' in s]}
 (O/'stereo-output-validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8');print(data['messages'],flush=True)
 raise SystemExit(0 if data['passed'] else 1)
if __name__=='__main__':main()
