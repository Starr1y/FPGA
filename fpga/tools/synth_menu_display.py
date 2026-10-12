"""Unplaced menu renderer synthesis; no board pin assignments or download."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,xml.etree.ElementTree as ET,argparse
R=Path(__file__).resolve().parents[2];W=R/'fpga/controls_display';O=R/'board-test/menu-display'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(bridge=False):
 O.mkdir(parents=True,exist_ok=True)
 name='menu_bridge' if bridge else 'menu_display';tcl='bridge_synthesis.tcl' if bridge else 'synthesis.tcl'
 files=[p for p in (W/'rtl').iterdir() if p.suffix in ('.v','.vh','.hex')]+[W/(name+'.gprj'),W/tcl]
 if bridge:files+=list((R/'fpga/controls/rtl').glob('*.v'))
 before={p.relative_to(R).as_posix():sha(p) for p in files}
 with tempfile.TemporaryDirectory(prefix='menu-display-') as temporary:
  t=Path(temporary)/'run.tcl';t.write_text('if {[catch {source '+tcl+'} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/('bridge-gowin-synthesis.log' if bridge else 'gowin-synthesis.log')).open('w',encoding='utf8') as log:
   a=subprocess.run(['D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(t)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 assert a.returncode==0,'See synthesis log'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'inputs changed'
 report=W/'impl/gwsynthesis'/(name+'_syn_rsc.xml');root=ET.parse(report).getroot()
 resources={k:v for k,v in root.attrib.items() if k.startswith('T_')}
 assert not list((W/'impl').rglob('*.fs')),'Standalone display synthesis must not produce board firmware'
 assert not any(('MULT' in n or 'DSP' in n) and not v.startswith('0') for n,v in resources.items()),'Menu unexpectedly consumes DSPs'
 data={'passed':True,'source_sha256':before,'resources':resources,'resource_scope':'controls + CDC + menu renderer, unplaced synthesis' if bridge else 'menu_panel only, unplaced synthesis',
  'timing_verified':False,'pin_mapping_verified':False,'board_firmware_generated':False,'integrated_into_duo02':False,'report_sha256':sha(report)}
 (O/('bridge-synthesis-validation.json' if bridge else 'synthesis-validation.json')).write_text(json.dumps(data,indent=2)+'\n',encoding='utf8');print(resources,flush=True)
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--bridge',action='store_true');main(parser.parse_args().bridge)
