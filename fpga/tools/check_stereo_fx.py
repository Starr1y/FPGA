"""Digital stereo effects checks; does not build or download a board image."""
from pathlib import Path
import subprocess,hashlib,json
from concurrent.futures import ThreadPoolExecutor
R=Path(__file__).resolve().parents[2];O=R/'board-test/stereo-fx'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=[R/'fpga/effects/rtl/stereo_fx.v']+sorted((R/'fpga/effects/tb').glob('*.sv'))
 before={p.relative_to(R).as_posix():sha(p) for p in files}
 def run(top):
  target=O/(top+'.vvp');cmd='iverilog -g2012 -s '+top+' -o '+q(linux(target))+' '+' '.join(q(linux(p)) for p in files)+' && vvp '+q(linux(target))
  a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
  text=a.stdout.decode('utf8',errors='replace');errors=a.stderr.decode('utf8',errors='replace')
  (O/(top+'.log')).write_text(text+'\n'+errors,encoding='utf8')
  passed=a.returncode==0 and 'TB_PASS' in text
  print(top,text.strip(),flush=True)
  if not passed:print(errors,flush=True)
  return top,{'passed':passed,'messages':text.splitlines()}
 with ThreadPoolExecutor(max_workers=3) as pool:results=dict(pool.map(run,['tb_stereo_fx','tb_stereo_fx_fraction','tb_stereo_fx_full']))
 passed=all(v['passed'] for v in results.values())
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'sources changed'
 data={'passed':passed,'source_sha256':before,'clock_hz':50000000,'simulation_ring_samples':32,'default_ring_samples':16384,
  'transaction_clocks':8,'integrated_into_board_top':False,'physical_audio_tested':False,'tests':results}
 (O/'validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
 raise SystemExit(0 if passed else 1)
if __name__=='__main__':main()
