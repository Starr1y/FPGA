"""Unplaced parameter output or menu/synth/FX/DAC synthesis, no board firmware."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,xml.etree.ElementTree as ET,shutil
R=Path(__file__).resolve().parents[2];W=R/'fpga/controlled_audio';O=R/'board-test/controlled-audio'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(performance=False):
 O.mkdir(parents=True,exist_ok=True)
 name='menu_performance' if performance else 'parameter_output';tcl='performance_synthesis.tcl' if performance else 'output_synthesis.tcl'
 files=list((W/'rtl').glob('*.v'))+list((W/'rtl').glob('*.hex'))+[W/(name+'.gprj'),W/tcl]
 if performance:
  files+=[R/'fpga/controls/rtl/instrument_menu.v']+[R/'fpga/duo02/rtl'/n for n in ['dual_note_map.v','dual_voice_scheduler.v','dual_audio_core.v','two_hand_synth.v','two_hand_event_queue.v','timbre_presets.v','sine_lut.v','instrument_waves.v','fm_limits.v','pt8211_output.v']]
 files+=[R/'fpga/duo02/rtl/stereo_fx.v']
 before={p.relative_to(R).as_posix():sha(p) for p in files}
 for p in (W/'rtl').glob('*.hex'):assert sha(p)==sha(R/'fpga/duo02/rtl'/p.name),'ROM differs from frozen audio source'
 with tempfile.TemporaryDirectory(prefix='controlled-audio-') as temporary:
  wrapper=Path(temporary)/'run.tcl';wrapper.write_text('if {[catch {source '+tcl+'} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/(name+'-synthesis.log')).open('w',encoding='utf8') as log:
   a=subprocess.run(['D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(wrapper)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 assert a.returncode==0,'See synthesis log'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files},'source changed during synthesis'
 report=W/'impl/gwsynthesis'/(name+'_syn_rsc.xml');counts={k:v for k,v in ET.parse(report).getroot().attrib.items() if k.startswith('T_')}
 assert not list((W/'impl').rglob('*.fs')),'Unplaced check must not generate board firmware'
 dest=R/'fpga/reports/controlled_audio'/name;dest.mkdir(parents=True,exist_ok=True)
 for p in report.parent.glob(name+'*'):
  if p.suffix in ('.html','.xml'):shutil.copyfile(p,dest/p.name)
 data={'passed':True,'source_sha256':before,'resources':counts,'top':name,'voices':32 if performance else None,
       'ring_samples_per_channel':16384,'timing_verified':False,'pin_mapping_verified':False,'board_firmware_generated':False,
       'includes_mechanical_filters':False,'includes_i2c_or_hdmi':False,'report_sha256':sha(report)}
 (O/(name+'-synthesis-validation.json')).write_text(json.dumps(data,indent=2)+'\n',encoding='utf8');print(counts,flush=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--performance',action='store_true');main(p.parse_args().performance)
