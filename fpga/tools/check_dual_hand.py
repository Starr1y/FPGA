"""Check the reusable dual-hand core against pinned FAN04 sources; no board access."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,subprocess,os,shutil
R=Path(__file__).resolve().parents[2];W=R/'fpga/dualhand';B=R/'fpga/i2cfan04';O=R/'board-test/dual-hand'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=sorted((W/'rtl').glob('*.v'))+sorted((W/'tb').glob('*.sv'))
 names=('bno_i2c_host.v','shtp_i2c_link.v','i2c_byte_master.v','shtp_report_decode.v','quaternion_pose.v','pose_math.v','gesture_control.v','expression_stream_guard.v','hand_expression.v')
 files+=[B/'rtl'/n for n in names]
 snapshot={p.relative_to(R).as_posix():sha(p) for p in files}
 cases=[('queue-depth-'+str(d),'tb_two_hand_queue',d) for d in (1,3,8)]+[('native-dual-hand','tb_two_hand_native',None)]
 def run(case):
  name,top,depth=case;target=O/(name+'.vvp');flags=['-P',f'tb_two_hand_queue.DEPTH={depth}'] if depth is not None else []
  if shutil.which('iverilog') and shutil.which('vvp'):
   compile_cmd=['iverilog','-g2012','-s',top,*flags,'-o',str(target),*[str(p) for p in files]];run_cmd=['vvp',str(target)]
  else:
   assert os.name=='nt' and shutil.which('wsl'),'Install Icarus Verilog or WSL Ubuntu with Icarus'
   prefix=['wsl','-d','Ubuntu','-e','bash','-lc']
   compile_cmd=prefix+['iverilog -g2012 -s '+top+' '+ ' '.join(flags)+' -o '+q(linux(target))+' '+' '.join(q(linux(p)) for p in files)]
   run_cmd=prefix+['vvp '+q(linux(target))]
  compiled=subprocess.run(compile_cmd,capture_output=True);ran=subprocess.run(run_cmd,capture_output=True) if not compiled.returncode else compiled
  output=ran.stdout.decode('utf8',errors='replace');errors=compiled.stderr.decode('utf8',errors='replace')
  if ran is not compiled:errors+=ran.stderr.decode('utf8',errors='replace')
  (O/(name+'.log')).write_text(output+'\n'+errors,encoding='utf8')
  result={'passed':ran.returncode==0 and 'TB_PASS' in output,'exit_code':ran.returncode,'messages':[s for s in output.splitlines() if 'TB_PASS' in s or 'FATAL' in s]}
  print(name,result,flush=True);return name,result
 with ThreadPoolExecutor(max_workers=4) as pool:results=dict(pool.map(run,cases))
 assert snapshot=={p.relative_to(R).as_posix():sha(p) for p in files},'simulation inputs changed'
 data={'source_sha256':snapshot,'tests':results,'inputs_unchanged':True,'native_clock_hz':1000000,'native_i2c_hz_upper_bound':250000,'native_pose_hz':100,
  'physical_dual_hand_tested':False,'board_download_top':False,'integrated_into_FAN04':False,'audio_connected':False,'passed':all(v['passed'] for v in results.values())}
 (O/'validation.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 raise SystemExit(0 if data['passed'] else 1)
if __name__=='__main__':main()
