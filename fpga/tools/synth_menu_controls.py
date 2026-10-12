"""Synthesis only, no pin assignment or firmware download."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[2];W=R/'fpga/controls';O=R/'board-test/controls'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=list((W/'rtl').glob('*.v'))+[W/'menu_controls.gprj',W/'synthesis.tcl']
 before={p.relative_to(R).as_posix():sha(p) for p in files}
 with tempfile.TemporaryDirectory(prefix='menu-controls-') as temporary:
  t=Path(temporary)/'run.tcl';t.write_text('if {[catch {source synthesis.tcl} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/'gowin-synthesis.log').open('w',encoding='utf8') as log:
   a=subprocess.run(['D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(t)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 assert a.returncode==0,'See synthesis log'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'sources changed'
 report=W/'impl/gwsynthesis/menu_controls_syn_rsc.xml';root=ET.parse(report).getroot()
 resources={k:v for k,v in root.attrib.items() if k.startswith('T_')}
 assert not list((W/'impl').rglob('*.fs')),'Synthesis-only control check must not generate board firmware'
 data={'passed':True,'source_sha256':before,'resources':resources,'resource_scope':'menu_control_core only, unplaced synthesis',
  'pin_mapping_verified':False,'timing_verified':False,'board_firmware_generated':False,'report_sha256':sha(report)}
 (O/'synthesis-validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8');print(resources,flush=True)
if __name__=='__main__':main()
