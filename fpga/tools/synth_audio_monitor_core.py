"""Unplaced combined FFT/snapshot synthesis; no board project or download."""
from pathlib import Path
import json,subprocess,tempfile,xml.etree.ElementTree as ET,shutil
from synth_audio_observer import sha
R=Path(__file__).resolve().parents[2];W=R/'fpga/audio_scope';O=R/'board-test/audio-scope'
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=list((W/'rtl').glob('*'))+[R/'fpga/audio_monitor/rtl/stereo_fft_observer.v',W/'audio_monitor_core.gprj',W/'synthesis.tcl',Path(__file__),R/'fpga/tools/synth_audio_observer.py']
 before={p.relative_to(R).as_posix():sha(p) for p in files if p.is_file()}
 for p in (W/'rtl').glob('*.hex'):assert sha(p)==sha(R/'fpga/audio_monitor/rtl'/p.name)
 with tempfile.TemporaryDirectory(prefix='audio-monitor-core-') as temporary:
  t=Path(temporary)/'run.tcl';t.write_text('if {[catch {source synthesis.tcl} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/'synthesis.log').open('w',encoding='utf8') as log:
   a=subprocess.run(['D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(t)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 assert a.returncode==0,'See existing synthesis.log'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files if p.is_file()}
 report=W/'impl/gwsynthesis/audio_monitor_core_syn_rsc.xml';counts={k:v for k,v in ET.parse(report).getroot().attrib.items() if k.startswith('T_')}
 assert not list((W/'impl').rglob('*.fs'))
 dest=R/'fpga/reports/audio-scope';dest.mkdir(parents=True,exist_ok=True)
 for p in report.parent.glob('audio_monitor_core*'):
  if p.suffix in ('.html','.xml'):shutil.copyfile(p,dest/p.name)
 d={'passed':True,'source_sha256':before,'resources':counts,'top':'audio_monitor_core',
    'timing_verified':False,'board_firmware_generated':False,'physical_tested':False,
    'report_sha256':{p.relative_to(R).as_posix():sha(p) for p in dest.iterdir() if p.is_file()}}
 (O/'synthesis-validation.json').write_text(json.dumps(d,indent=2)+'\n',encoding='utf8');print(json.dumps(counts,indent=2),flush=True)
if __name__=='__main__':main()
