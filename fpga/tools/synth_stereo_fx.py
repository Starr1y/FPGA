"""Check default-capacity stereo FX RAM inference with Gowin synthesis only."""
from pathlib import Path
import json,subprocess,tempfile,hashlib,re,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[2];W=R/'fpga/effects';O=R/'board-test/stereo-fx'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=[W/'rtl/stereo_fx.v',W/'stereo_fx.gprj',W/'synthesis.tcl']
 before={p.relative_to(R).as_posix():sha(p) for p in files}
 with tempfile.TemporaryDirectory(prefix='stereo-fx-syn-') as temporary:
  t=Path(temporary)/'run.tcl';t.write_text('if {[catch {source synthesis.tcl} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/'gowin-synthesis.log').open('w',encoding='utf8') as log:
   result=subprocess.run(['D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(t)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 assert result.returncode==0,'See synthesis log'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'inputs changed during synthesis'
 report=W/'impl/gwsynthesis/stereo_fx_syn_rsc.xml';root=ET.parse(report).getroot()
 counts={k:v for k,v in root.attrib.items() if k.startswith('T_')}
 netlist=W/'impl/gwsynthesis/stereo_fx.vg';data=netlist.read_text()
 blocks=re.findall(r'^\s*SDPB\s+(memory_(?:left|right)_\w+)\s*\(',data,re.M)
 assert len(blocks)==32 and sum(n.startswith('memory_left_') for n in blocks)==16 and sum(n.startswith('memory_right_') for n in blocks)==16,'Expected 16 simple dual-port BSRAMs per channel'
 assert not list((W/'impl').rglob('*.fs')),'Synthesis check must not create board firmware'
 (O/'synthesis-validation.json').write_text(json.dumps({'passed':True,'source_sha256':before,'resources':counts,
  'resource_scope':'standalone stereo_fx at default 16384 samples/channel; unplaced synthesis',
  'timing_verified':False,'board_pins_assigned':False,'bitstream_generated':False,'simple_dual_port_ram_instances':len(blocks),
  'report_sha256':sha(report),'netlist_sha256':sha(netlist)},indent=2)+'\n',encoding='utf8')
 print(json.dumps(counts,indent=2),flush=True)
if __name__=='__main__':main()
