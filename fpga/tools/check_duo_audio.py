"""Exercise DUO01's pipelined Voice allocator against the shared audio benches."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo01';O=R/'board-test/duo01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def main():
 O.mkdir(parents=True,exist_ok=True)
 names=['dual_note_map.v','dual_voice_scheduler.v','dual_audio_core.v','two_hand_synth.v','two_hand_event_queue.v','timbre_presets.v','sine_lut.v','instrument_waves.v','fm_limits.v']
 files=[W/'rtl'/n for n in names]+[R/'fpga/dualhand/tb'/n for n in ['tb_dual_note_map.sv','tb_dual_synth.sv']]
 inputs=files+list((W/'rtl').glob('*.hex'))
 before={p.relative_to(R).as_posix():sha(p) for p in inputs}
 def run(case):
  name,top,voices=case;target=O/(name+'.vvp');flags=f'-P tb_dual_synth.VOICES={voices}' if voices else ''
  cmd='cd '+q(linux(W))+' && iverilog -g2012 -s '+top+' '+flags+' -o '+q(linux(target))+' '+' '.join(q(linux(p)) for p in files)+' && vvp '+q(linux(target))
  a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
  output=a.stdout.decode('utf8',errors='replace');errors=a.stderr.decode('utf8',errors='replace')
  (O/(name+'.log')).write_text(output+'\n'+errors,encoding='utf8')
  result={'passed':a.returncode==0 and 'TB_PASS' in output,'exit_code':a.returncode,'messages':[s for s in output.splitlines() if 'TB_PASS' in s or 'FATAL' in s]}
  print(name,result,flush=True);return name,result
 cases=[('note-map','tb_dual_note_map',None)]+[(f'synth-{v}','tb_dual_synth',v) for v in (8,32)]
 with ThreadPoolExecutor(max_workers=3) as pool:results=dict(pool.map(run,cases))
 assert before=={p.relative_to(R).as_posix():sha(p) for p in inputs},'sources changed'
 data={'passed':all(v['passed'] for v in results.values()),'source_sha256':before,'tests':results,'clock_hz':50000000,'sample_hz':48000,'physical_audio_tested':False}
 (O/'audio-validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
 raise SystemExit(0 if data['passed'] else 1)
if __name__=='__main__':main()
