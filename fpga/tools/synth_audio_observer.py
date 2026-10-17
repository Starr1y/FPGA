"""Synthesize passive FFT observer only. Does not create/download board firmware."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,xml.etree.ElementTree as ET,shutil
R=Path(__file__).resolve().parents[2];W=R/'fpga/audio_monitor';O=R/'board-test/audio-monitor'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=list((W/'rtl').glob('*'))+[W/'audio_observer.gprj',W/'observer_synthesis.tcl',Path(__file__)]
 before={p.relative_to(R).as_posix():sha(p) for p in files if p.is_file()}
 with tempfile.TemporaryDirectory(prefix='fft-observer-') as temporary:
  t=Path(temporary)/'run.tcl';t.write_text('if {[catch {source observer_synthesis.tcl} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/'synthesis.log').open('w',encoding='utf8') as log:
   a=subprocess.run(['D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(t)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 assert a.returncode==0,'See existing synthesis.log'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files if p.is_file()},'source changed'
 report=W/'impl/gwsynthesis/audio_observer_syn_rsc.xml';root=ET.parse(report).getroot()
 counts={k:v for k,v in root.attrib.items() if k.startswith('T_')}
 assert not list((W/'impl').rglob('*.fs')),'component synthesis is not firmware'
 dest=R/'fpga/reports/audio-monitor';dest.mkdir(parents=True,exist_ok=True)
 for p in report.parent.glob('audio_observer*'):
  if p.suffix in ('.html','.xml'):shutil.copyfile(p,dest/p.name)
 d={'passed':True,'source_sha256':before,'resources':counts,'top':'stereo_fft_observer',
    'timing_verified':False,'pin_mapping_verified':False,'board_firmware_generated':False,
    'integrated_into_board_top':False,'physical_tested':False,
    'report_sha256':{p.relative_to(R).as_posix():sha(p) for p in dest.iterdir() if p.is_file()}}
 (O/'synthesis-validation.json').write_text(json.dumps(d,indent=2)+'\n',encoding='utf8');print(json.dumps(counts,indent=2),flush=True)
if __name__=='__main__':main()
