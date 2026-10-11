"""Digital dual-hand event/Voice/PCM checks; no board access or host GUI."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,subprocess,shutil,os,argparse
R=Path(__file__).resolve().parents[2]; O=R/'board-test/dual-audio'; D=R/'fpga/dualhand/synthdeps'
NAMES=['dual_note_map.v','dual_voice_scheduler.v','dual_audio_core.v','two_hand_synth.v','two_hand_event_queue.v']
DEPS=['timbre_presets.v','sine_lut.v','instrument_waves.v','fm_limits.v']
ROMS=['midi_ftw.hex','cent_ratio.hex','instrument_dark.hex','instrument_bright.hex','instrument_gain.hex','fm_limits.hex']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def quote(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--native-only',action='store_true');args=parser.parse_args()
 O.mkdir(parents=True,exist_ok=True)
 files=[R/'fpga/dualhand/rtl'/n for n in NAMES]+[D/'rtl'/n for n in DEPS]
 files+=[R/'fpga/dualhand/tb'/n for n in ['tb_dual_note_map.sv','tb_dual_synth.sv']]
 if args.native_only:
  files += [R/'fpga/dualhand/rtl'/n for n in ['two_hand_instrument_core.v','two_hand_i2c_core.v','bno_i2c_hand.v']]
  files += [R/'fpga/dualhand/tb'/n for n in ['tb_dual_sensor_audio.sv','bno_two_hand_peer.sv']]
  files += [R/'fpga/i2cfan04/rtl'/n for n in ['bno_i2c_host.v','shtp_i2c_link.v','i2c_byte_master.v','shtp_report_decode.v','quaternion_pose.v','pose_math.v','gesture_control.v','expression_stream_guard.v','hand_expression.v']]
 inputs=files+[D/'rtl'/n for n in ROMS]+[D/'reference_audio_core.v']
 snapshot={p.relative_to(R).as_posix():sha(p) for p in inputs}
 cases=[('note-map','tb_dual_note_map',None)]+[(f'synth-{v}','tb_dual_synth',v) for v in (8,32)]
 if args.native_only:cases=[('native-sensor-audio','tb_dual_sensor_audio',None)]
 def run(case):
  name,top,voices=case;target=O/(name+'.vvp');flags=['-P',f'tb_dual_synth.VOICES={voices}'] if voices else []
  if shutil.which('iverilog') and shutil.which('vvp'):
   cc=['iverilog','-g2012','-s',top,*flags,'-o',str(target),*[str(p) for p in files]]
   rr=['vvp',str(target)]
  else:
   assert os.name=='nt' and shutil.which('wsl'),'Install Icarus Verilog or WSL Ubuntu with Icarus'
   prefix=['wsl','-d','Ubuntu','-e','bash','-lc']
   cc=prefix+['iverilog -g2012 -s '+top+' '+' '.join(flags)+' -o '+quote(linux(target))+' '+' '.join(quote(linux(p)) for p in files)]
   rr=prefix+['cd '+quote(linux(D))+' && vvp '+quote(linux(target))]
  c=subprocess.run(cc,capture_output=True);a=subprocess.run(rr,capture_output=True,cwd=D) if c.returncode==0 else c
  output=a.stdout.decode('utf8',errors='replace');errors=c.stderr.decode('utf8',errors='replace')
  if a is not c:errors+=a.stderr.decode('utf8',errors='replace')
  (O/(name+'.log')).write_text(output+'\n'+errors,encoding='utf8')
  result={'passed':a.returncode==0 and 'TB_PASS' in output,'exit_code':a.returncode,'messages':[s for s in output.splitlines() if 'TB_PASS' in s or 'FATAL' in s]}
  print(name,result,flush=True);return name,result
 with ThreadPoolExecutor(max_workers=3) as pool:results=dict(pool.map(run,cases))
 assert snapshot=={p.relative_to(R).as_posix():sha(p) for p in inputs},'simulation sources changed'
 data={'source_sha256':snapshot,'tests':results,'clock_hz':50000000,'sample_hz':48000,'event_input':'digital queue injection',
       'physical_audio_tested':False,'native_sensor_to_audio_tested':args.native_only,'board_download_top':False,'integrated_into_FAN04':False,
       'passed':all(x['passed'] for x in results.values())}
 if args.native_only:data.update(clock_hz=1000000,sample_hz=2000,event_input='pin-level two I2C sensor peers; shortened boot/reset test parameters')
 (O/('native-validation.json' if args.native_only else 'validation.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 raise SystemExit(0 if data['passed'] else 1)
if __name__=='__main__':main()
