"""Menu-to-synth and parameter output checks. No download or physical proof."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse,hashlib,json,subprocess
R=Path(__file__).resolve().parents[2];W=R/'fpga/controlled_audio';O=R/'board-test/controlled-audio'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def inputs():
 names=['dual_note_map.v','dual_voice_scheduler.v','dual_audio_core.v','two_hand_synth.v','two_hand_event_queue.v','timbre_presets.v','sine_lut.v','instrument_waves.v','fm_limits.v','stereo_fx.v','pt8211_output.v']
 files=list((W/'rtl').glob('*.v'))+[R/'fpga/duo02/rtl'/n for n in names]+[R/'fpga/controls/rtl/instrument_menu.v']+list((W/'tb').glob('*.sv'))
 # Run with the same relative ROM paths as the new synthesis project.
 inputs=sorted(set(files+list((W/'rtl').glob('*.hex'))))
 for p in (W/'rtl').glob('*.hex'):assert sha(p)==sha(R/'fpga/duo02/rtl'/p.name),'ROM differs from frozen audio source'
 return files,inputs+[Path(__file__).resolve()]
def verify():
 _,files=inputs();data=json.loads((O/'validation.json').read_text(encoding='utf8'))
 assert data['passed'] and set(data['tests'])=={'tb_parameter_stereo_output','tb_menu_performance_core'}
 assert all(t['passed'] and t['exit_code']==0 for t in data['tests'].values())
 assert data['source_sha256']=={p.relative_to(R).as_posix():sha(p) for p in files},'validation source set/bytes changed'
 for n,d in data['log_sha256'].items():assert sha(O/n)==d,n
 for name in ('parameter_output','menu_performance'):
  syn=json.loads((O/(name+'-synthesis-validation.json')).read_text(encoding='utf8'));assert syn['passed']
  for n,d in syn['source_sha256'].items():assert sha(R/n)==d,n
  report=R/'fpga/reports/controlled_audio'/name/(name+'_syn_rsc.xml')
  assert sha(report)==syn['report_sha256'],'published synthesis report'
 print('PASS controlled audio test inputs/logs and unplaced synthesis reports; no hardware validation')
def main():
 O.mkdir(parents=True,exist_ok=True);files,source_inputs=inputs()
 before={p.relative_to(R).as_posix():sha(p) for p in source_inputs}
 def run(top):
  cmd='cd '+q(linux(W))+' && iverilog -g2012 -Wall -s '+top+' -o '+q(linux(O/(top+'.vvp')))+' '+' '.join(q(linux(p)) for p in files)+' && stdbuf -oL vvp '+q(linux(O/(top+'.vvp')))
  a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
  text=(a.stdout+a.stderr).decode('utf8',errors='replace');(O/(top+'.log')).write_text(text,encoding='utf8')
  result={'passed':a.returncode==0 and 'TB_PASS' in text and 'ERROR:' not in text and 'FATAL:' not in text,
          'exit_code':a.returncode,'messages':[s for s in text.splitlines() if 'TB_PASS' in s or 'FATAL' in s or 'error:' in s]}
  print(top,result,flush=True);return top,result
 with ThreadPoolExecutor(max_workers=2) as pool:tests=dict(pool.map(run,['tb_parameter_stereo_output','tb_menu_performance_core']))
 assert before=={p.relative_to(R).as_posix():sha(p) for p in source_inputs},'sources changed during validation'
 data={'passed':all(v['passed'] for v in tests.values()),'source_sha256':before,'tests':tests,'clock_hz':50000000,'sample_hz':48000,'voices':32,'ring_samples_per_channel':16384,
       'menu_input_scope':'semantic pulses, mechanical filters tested separately','sensor_inputs':'synthetic gesture event payloads, no I2C in this test',
       'physical_audio_tested':False,'board_pin_map_present':False,'integrated_into_duo02':False,
       'log_sha256':{n+'.log':sha(O/(n+'.log')) for n in tests}}
 (O/'validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
 raise SystemExit(0 if data['passed'] else 1)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--verify',action='store_true')
 if p.parse_args().verify:verify()
 else:main()
