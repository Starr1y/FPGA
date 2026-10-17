"""Actual FFT to pixel RAM reference check; no PLL/TMDS or board download."""
from pathlib import Path
import json,subprocess,argparse
import numpy as np
import check_audio_observer as c
from check_audio_snapshot import band
R=c.R;W=R/'fpga/audio_scope';O=R/'board-test/audio-scope'
def verify():
 d=json.loads((O/'core-validation.json').read_text(encoding='utf8'));assert d['passed']
 for n,h in d['source_sha256'].items():assert c.sha(R/n)==h,n
 for n,h in d['evidence_sha256'].items():assert c.sha(O/n)==h,n
 print('PASS real FFT to atomic pixel frame evidence; no RGB/board proof')
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=[c.W/'rtl/stereo_fft_observer.v',W/'rtl/audio_observer_snapshot.v',W/'rtl/audio_monitor_core.v',W/'tb/tb_audio_monitor_core.sv']
 roms=list((c.W/'rtl').glob('*.hex'))
 for p in roms:assert c.sha(p)==c.sha(W/'rtl'/p.name),'ROM copy must equal tested FFT coefficients'
 inputs=files+roms+[W/'rtl'/p.name for p in roms]+[Path(__file__),R/'fpga/tools/check_audio_observer.py',R/'fpga/tools/check_audio_snapshot.py']
 before={p.relative_to(R).as_posix():c.sha(p) for p in inputs}
 source=c.O/'input.hex';assert source.is_file(),'run check_audio_observer first'
 output=O/'core-words.txt';compiled=O/'core.vvp'
 cmd='cd '+c.q(c.linux(W))+' && iverilog -g2012 -s tb_audio_monitor_core -o '+c.q(c.linux(compiled))+' '+' '.join(c.q(c.linux(p)) for p in files)+' && vvp '+c.q(c.linux(compiled))+' '+c.q('+DATA='+c.linux(source))+' '+c.q('+RESULT='+c.linux(output))
 a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
 log=a.stdout.decode('utf8',errors='replace')+'\n'+a.stderr.decode('utf8',errors='replace');(O/'core.log').write_text(log,encoding='utf8')
 assert a.returncode==0 and 'TB_PASS' in log,log[-3000:]
 h=[int(s,16) for s in (c.W/'rtl/fft_hann.hex').read_text().split()]
 t=[(c.signed(int(s,16)>>16,16),c.signed(int(s,16)&65535,16)) for s in (c.W/'rtl/fft_twiddle.hex').read_text().split()]
 cases=c.vectors();expected={};total=0
 for frame,vector in enumerate((3,5,7)):
  row=[0]*512
  for ch,x in enumerate(cases[vector]):
   bins=c.integer_fft(x,h,t)
   for col in range(64):
    seg=x[col*16:col*16+16];row[ch*64+col]=((int(max(seg))&65535)<<16)|(int(min(seg))&65535)
   for k,(re,im) in enumerate(bins[1:],1):
    address=128+ch*64+band(k);row[address]=max(row[address],abs(re)+abs(im))
  for v in range(32):row[256+v]=((1000+v*500)<<10)|((48+v)<<3)|(((0xaaaa5555>>v)&1)<<2)|(((0x3333cccc>>v)&1)<<1)|((0xf0f00f0f>>v)&1)
  row[288:292]=[frame,120836,0,0];expected[frame]=row
 seen=set()
 for line in output.read_text().splitlines():
  tag,f,addr,value=line.split();f=int(f);addr=int(addr);value=int(value,16)
  assert tag=='R' and (f,addr) not in seen;seen.add((f,addr));assert value==expected[f][addr],('real FFT pixel mismatch',f,addr,value,expected[f][addr]);total+=1
 assert total==1536 and before=={p.relative_to(R).as_posix():c.sha(p) for p in inputs}
 d={'passed':True,'source_sha256':before,'evidence_sha256':{p.name:c.sha(p) for p in (output,O/'core.log')},
    'input_fixture_sha256':c.sha(source),'core_clock_hz':50000000,'pixel_clock_hz':25000000,'pcm_hz':48000,
    'complete_stereo_frames':3,'pixel_words_checked':total,'voice_metadata':32,'real_fft_connected':True,
    'pixel_commit_period_cycles':420000,'commit_in_blank_cycle':383999,'monitor_drops':0,'snapshot_skips':0,'invalid_frames':0,
    'hdmi_rgb_rendered':False,'timing_verified':False,'physical_tested':False}
 (O/'core-validation.json').write_text(json.dumps(d,indent=2)+'\n',encoding='utf8');print(log.split('TB_PASS')[-1].splitlines()[0])
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--verify',action='store_true');a=p.parse_args();verify() if a.verify else main()
