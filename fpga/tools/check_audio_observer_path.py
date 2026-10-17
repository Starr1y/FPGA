"""Tap the unchanged 32-Voice/FX/DAC bench and check actual PCM against FFT."""
from pathlib import Path
import json,subprocess
import numpy as np
import check_audio_observer as c
R,W,O=c.R,c.W,c.O
def main():
 O.mkdir(parents=True,exist_ok=True)
 names=['dual_note_map.v','dual_voice_scheduler.v','dual_audio_core.v','two_hand_synth.v','two_hand_event_queue.v','timbre_presets.v','sine_lut.v','instrument_waves.v','fm_limits.v','stereo_fx.v','stereo_output_path.v','pt8211_output.v']
 files=[R/'fpga/duo03/rtl'/n for n in names]+[R/'fpga/duo03/tb/tb_dual_synth.sv',W/'rtl/stereo_fft_observer.v',W/'tb/tb_synth_observer.sv']
 roms=list((R/'fpga/duo03/rtl').glob('*.hex'))+list((W/'rtl').glob('*.hex'))
 inputs=files+roms+[Path(__file__),R/'fpga/tools/check_audio_observer.py']
 before={p.relative_to(R).as_posix():c.sha(p) for p in inputs}
 # Audio source ROM paths are relative to the DUO03 project; FFT ROMs use the
 # same rtl directory spelling, so stage only the two new files in a temp cwd.
 import tempfile,shutil
 output=O/'synth-numeric.txt';compiled=O/'synth-observer.vvp'
 with tempfile.TemporaryDirectory(prefix='actual-pcm-observer-') as temporary:
  cwd=Path(temporary);(cwd/'rtl').mkdir()
  for source in roms:shutil.copyfile(source,cwd/'rtl'/source.name)
  cmd='cd '+c.q(c.linux(cwd))+' && iverilog -g2012 -s tb_synth_observer -o '+c.q(c.linux(compiled))+' '+' '.join(c.q(c.linux(p)) for p in files)+' && vvp '+c.q(c.linux(compiled))+' '+c.q('+RESULT='+c.linux(output))
  a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
 log=a.stdout.decode('utf8',errors='replace')+'\n'+a.stderr.decode('utf8',errors='replace');(O/'synth-observer.log').write_text(log,encoding='utf8')
 assert a.returncode==0 and 'TB_PASS 32 Voices:' in log,log[-3000:]
 pcm={};bins={};waves={};done={}
 for line in output.read_text().splitlines():
  tag,*v=line.split();v=[int(x) for x in v]
  if tag=='P':pcm.setdefault(v[0],[]).append(v[1:])
  elif tag=='D':key=tuple(v[:2]);assert key not in done;done[key]=v[2:]
  elif tag in ('B','W'):
   dest=bins if tag=='B' else waves;key=tuple(v[:4]);assert key not in dest;dest[key]=tuple(v[4:])
 assert len(done)>=2,'need two complete real PCM frames'
 h=[int(v,16) for v in (W/'rtl/fft_hann.hex').read_text().split()]
 t=[(c.signed(int(v,16)>>16,16),c.signed(int(v,16)&65535,16)) for v in (W/'rtl/fft_twiddle.hex').read_text().split()]
 checked=0;max_error=0;nonzero=0;different=0
 for (epoch,frame),(drops,count,cycles) in done.items():
  x=np.array(pcm[epoch][frame*1024:(frame+1)*1024]);assert x.shape==(1024,2)
  assert drops==0 and cycles<200000
  nonzero+=int(np.count_nonzero(x));different+=int(np.count_nonzero(x[:,0]!=x[:,1]))
  for ch in range(2):
   exact=c.integer_fft(x[:,ch],h,t);actual=[bins[(epoch,frame,ch,k)] for k in range(513)]
   assert exact==actual,('actual synthesis PCM/RTL FFT mismatch',epoch,frame,ch)
   av=np.array([complex(*v) for v in actual]);ref=np.fft.rfft(x[:,ch]*np.array(h)/32768,norm='forward')*256
   error=float(np.max(np.abs(av-ref)));assert error<256;max_error=max(max_error,error)
   for col in range(64):
    seg=x[col*16:(col+1)*16,ch];assert waves[(epoch,frame,ch,col)]==(int(min(seg)),int(max(seg)))
   checked+=513
 assert nonzero>100 and different>100,'must observe real nonidentical stereo audio'
 assert before=={p.relative_to(R).as_posix():c.sha(p) for p in inputs},'source changed'
 data={'passed':True,'source_sha256':before,'evidence_sha256':{p.name:c.sha(p) for p in (output,O/'synth-observer.log')},
       'complete_stereo_frames':len(done),'complex_bins_checked':checked,'actual_pcm_nonzero_values':nonzero,'different_channel_samples':different,
       'max_complex_error_q8':max_error,'tap':'pcm_valid/pcm_left/pcm_right after real 32-Voice default stereo reverb and mute gain, before real PT8211',
       'unchanged_source_bench':'fpga/duo03/tb/tb_dual_synth.sv','bench_assertions_retained':True,'physical_tested':False,'hdmi_integrated':False,'timing_verified':False}
 (O/'synth-path-validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
 print(json.dumps({k:v for k,v in data.items() if k not in ('source_sha256','evidence_sha256')},indent=2),flush=True)
if __name__=='__main__':main()
