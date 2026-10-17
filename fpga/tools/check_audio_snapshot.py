"""Two-clock snapshot integrity: every pixel word, bank handoff and invalid input."""
from pathlib import Path
import json,hashlib,subprocess,argparse
R=Path(__file__).resolve().parents[2];W=R/'fpga/audio_scope';O=R/'board-test/audio-scope'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def band(k):
 if k<=32:return max(0,k-1)
 lead=k.bit_length()-1
 return min(63,32+(lead-5)*8+((k>>(lead-3))&7))
def expected(frame,address):
 if frame==0 or address>=292:return 0
 if address<128:
  ch,col=divmod(address,64);lo=-1000-frame*10-col-ch*100;hi=2000+frame*10+col+ch*100
  return ((hi&65535)<<16)|(lo&65535)
 if address<256:
  ch,b=divmod(address-128,64);values=[]
  for k in range(1,513):
   if band(k)==b:values.append(16777216 if k==257 else (frame+1)*100+k*4+ch*11+20)
  assert values
  return max(values)
 if address<288:
  v=address-256;return ((frame*100+v*17)<<10)|(((frame+v+48)%128)<<3)|(((v+frame)%2)<<2)|(((v+frame)%4==0)<<1)|((v+frame)%3!=0)
 return [frame,120836+frame,frame,{1:0,2:1,9:0}[frame]][address-288]
def verify():
 d=json.loads((O/'validation.json').read_text(encoding='utf8'));assert d['passed']
 for n,h in d['source_sha256'].items():assert sha(R/n)==h,n
 for n,h in d['evidence_sha256'].items():assert sha(O/n)==h,n
 print('PASS dual-clock audio snapshot evidence; not board timing/physical proof')
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=[W/'rtl/audio_observer_snapshot.v',W/'tb/tb_audio_observer_snapshot.sv',Path(__file__)]
 before={p.relative_to(R).as_posix():sha(p) for p in files};output=O/'snapshot-words.txt';compiled=O/'snapshot.vvp'
 cmd='cd '+q(linux(W))+' && iverilog -g2012 -s tb_audio_observer_snapshot -o '+q(linux(compiled))+' '+' '.join(q(linux(p)) for p in files[:-1])+' && vvp '+q(linux(compiled))+' '+q('+RESULT='+linux(output))
 a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
 log=a.stdout.decode('utf8',errors='replace')+'\n'+a.stderr.decode('utf8',errors='replace');(O/'snapshot.log').write_text(log,encoding='utf8')
 assert a.returncode==0 and 'TB_PASS' in log,log[-3000:]
 counts={};total=0
 for line in output.read_text().splitlines():
  tag,f,address,value=line.split();f=int(f);address=int(address);value=int(value,16)
  assert tag=='R' and value==expected(f,address),('pixel word mismatch',f,address,hex(value),hex(expected(f,address)))
  counts[f]=counts.get(f,0)+1;total+=1
 assert total==3584 and counts=={0:1024,1:1024,2:1024,9:512}
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'source changed'
 d={'passed':True,'source_sha256':before,'evidence_sha256':{p.name:sha(p) for p in (output,O/'snapshot.log')},
    'core_clock_hz':50000000,'pixel_clock_hz':25000000,'nonaligned_clock_phase_ns':3.7,
    'pixel_words_checked':total,'frame_buffers':2,'memory_words_per_bank':512,'metadata_voices':32,
    'atomic_blank_swap_checked':True,'pending_bank_protected':True,'malformed_frame_rejected':True,'reset_aborts_partial_frame':True,
    'integrated_with_real_fft':False,'hdmi_rendered':False,'timing_verified':False,'physical_tested':False}
 (O/'validation.json').write_text(json.dumps(d,indent=2)+'\n',encoding='utf8');print(log.split('TB_PASS')[-1].splitlines()[0])
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--verify',action='store_true');a=p.parse_args();verify() if a.verify else main()
