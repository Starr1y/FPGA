"""Freeze DUO03 only after whole digital checks, traced pins and zero STA errors."""
from pathlib import Path
import argparse,json,re,shutil
from datetime import datetime,timezone
import duo03_release as c
R,W,O=c.R,c.W,c.O
def read(p):return json.loads(p.read_text(encoding='utf8'))
def main(inspect_only=False):
 assert read(O/'build-inputs.json')==c.inputs(),'rebuild after hardware changes'
 # Adjustable FX was copied byte-for-byte from the independently tested path.
 base=read(R/'board-test/controlled-audio/validation.json');assert base['passed']
 key='fpga/controlled_audio/rtl/parameter_stereo_output.v'
 assert c.sha(W/'rtl/parameter_stereo_output.v')==base['source_sha256'][key],'parameter output needs its own updated component test'
 pinmap=read(O/'pinmap.json');assert c.sha(R/pinmap['source'])==pinmap['source_sha256']
 log=(O/'gowin-build.log').read_text(encoding='utf8');assert 'Bitstream generation completed' in log and not re.search(r'^ERROR\b',log,re.M)
 name='tanglab_duo03';pnr=W/'impl/pnr';timing=(pnr/(name+'_tr_content.html')).read_text()
 violations={k.lower():int(re.search('Numbers of '+k+r' Violated Endpoints</td>\s*<td>(\d+)',timing)[1]) for k in ('Setup','Hold')}
 assert violations=={'setup':0,'hold':0},violations
 a=timing.index('Max Frequency Summary:');table=timing[a:timing.index('</table>',a)];freq={}
 for row in re.findall(r'<tr[^>]*>(.*?)</tr>',table,re.S):
  cells=re.findall(r'<td[^>]*>(.*?)</td>',row,re.S)
  if len(cells)>=4:freq[cells[1]]=float(cells[3].replace('(MHz)',''))
 assert freq['sys_clk']>=50 and next(v for k,v in freq.items() if 'CLKOUT1' in k)>=25,freq
 pins=(pnr/(name+'.pin.html')).read_text();rows=[re.findall(r'<td[^>]*>(.*?)</td>',r,re.S) for r in re.findall(r'<tr[^>]*>(.*?)</tr>',pins,re.S)]
 expected={};controls={}
 for item in pinmap['pins']:
  if 'hand' in item:
   signal={'SCL':'imu_scl','SDA':'imu_sda','INT':'imu_int_n','RST':'imu_rst_n'}[item['signal']]+f'[{item["hand"]}]';expected[signal]=item['fpga_ball']
  elif item.get('bank')==2:controls[item['signal']]=item['fpga_ball']
 assert len(expected)==8 and len(controls)==6
 for signal,ball in (expected|controls).items():
  row=next(r for r in rows if r and r[0].strip()==signal)
  assert row[2].strip()==ball+'/2' and 'LVCMOS33' in row,(signal,row)
  # Gowin 1.9.12 Ports & Pins: column4 is I/O direction; column1 is bus index.
  if signal in controls:assert row[4].strip().lower()=='in',(signal,row)
 vg=(W/'impl/gwsynthesis'/(name+'.vg')).read_text()
 for signal in [n for n in expected if not n.startswith('imu_int')]:
  primitive='TBUF' if signal.startswith('imu_rst') else 'IOBUF';pad='O' if primitive=='TBUF' else 'IO'
  blocks=re.findall(primitive+r'\s+\w+\s*\([^;]*?\);',vg,re.S)
  block=next(b for b in blocks if '.'+pad+'('+signal+')' in b)
  assert re.search(r"\.I\((?:GND|1'b0)\)",block),(signal,block)
 resources={};report=(pnr/(name+'.rpt.txt')).read_text()
 for key in ('Logic','Register','BSRAM','DSP'):
  m=re.search(r'^\s*'+key+r'\s*\|\s*([\d.]+)/([\d.]+)',report,re.M);assert m,key
  resources[key]={'used':float(m[1]),'available':float(m[2])}
 fs=pnr/(name+'.fs');assert fs.is_file(),'missing built bitstream'
 for directory in ('pnr','gwsynthesis'):
  dest=R/'fpga/reports/duo03'/directory;dest.mkdir(parents=True,exist_ok=True)
  for p in (W/'impl'/directory).glob(name+'*'):
   if p.suffix in ('.html','.txt'):shutil.copy2(p,dest/p.name)
 build_data={'passed':True,'scope':'Gowin build input/timing/pins/netlist inspection, not final release or physical proof',
  'source_sha256':{'fpga/duo03/'+n:d for n,d in c.inputs().items()},'timing_violations':violations,'fmax_mhz':freq,'resources':resources,
  'built_candidate_sha256':c.sha(fs),'imu_open_drain_pads_checked':6,'bank2_imu_pins_checked':8,'bank2_external_input_pins_checked':6,
  'physical_board_tested':False,'downloaded':False,
  'report_sha256':{p.relative_to(R).as_posix():c.sha(p) for p in (R/'fpga/reports/duo03').rglob('*') if p.is_file()}}
 (O/'build-validation.json').write_text(json.dumps(build_data,indent=2)+'\n',encoding='utf8')
 if inspect_only:
  print(json.dumps({k:build_data[k] for k in ('built_candidate_sha256','timing_violations','fmax_mhz','resources')},indent=2),flush=True)
  return
 c.verify() # Final publication still requires ALL independent digital checks.
 target=R/'fpga/bitstream'/(name+'.fs')
 assert not target.exists() or c.sha(target)==c.sha(fs),'never replace frozen firmware with different bytes'
 if not target.exists():shutil.copy2(fs,target)
 data={'project':'fpga/duo03/'+name+'.gprj','top':'top_duo03','firmware':target.relative_to(R).as_posix(),'sha256':c.sha(target),
  'version_marker':'DUO03','source_sha256':c.inputs(),'timing_violations':violations,'fmax_mhz':freq,'resources':resources,
  'physical_board_tested':False,'sram_downloaded':False,'flash_downloaded':False,'default_imu_enabled':[False,False],'default_muted':True,
  'pinmap':'board-test/duo03/pinmap.json','digital_manifests':[p.name for p in O.glob('*validation.json')],
  'audio_format':'independent stereo, adjustable delay/chorus/reverb, PT8211 LSBJ 48kHz','actual_dual_modules_verified':False,
  'physical_external_controls_verified':False,'analog_audio_verified':False,'motion_to_analog_latency_verified':False,
  'native_resolution':[640,480],'edid_negotiation_implemented':False,'completed_utc':datetime.now(timezone.utc).isoformat()}
 (O/'firmware.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print(json.dumps({k:data[k] for k in ('sha256','resources','fmax_mhz')},indent=2),flush=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--inspect-only',action='store_true');main(p.parse_args().inspect_only)
