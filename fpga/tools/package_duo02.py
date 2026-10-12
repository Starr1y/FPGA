"""Freeze DUO02 only after raster/key/native DAC checks and zero timing violations."""
from pathlib import Path
import json,re,shutil
from datetime import datetime,timezone
import duo02_release as c
R,W,O=c.R,c.W,c.O
def read(p):return json.loads(p.read_text(encoding='utf8'))
def main():
 c.verify();board=read(O/'board-path-validation.json');assert board['passed']
 audio=read(O/'audio-validation.json');assert audio['passed']
 output=read(O/'stereo-output-validation.json');assert output['passed']
 for n,d in output['source_sha256'].items():assert c.sha(R/n)==d,n
 for n,d in audio['source_sha256'].items():assert c.sha(R/n)==d,n
 for n,d in board['source_sha256'].items():assert c.sha(R/n)==d,n
 built=read(O/'build-inputs.json');assert built==c.inputs(),'Rebuild after source changes'
 pinmap=read(O/'pinmap.json');assert c.sha(R/pinmap['source'])==pinmap['source_sha256']
 log=(O/'gowin-build.log').read_text(encoding='utf8');assert 'Bitstream generation completed' in log
 assert not re.search(r'^ERROR\b',log,re.M)
 name='tanglab_duo02';pnr=W/'impl/pnr';timing=(pnr/(name+'_tr_content.html')).read_text()
 violations={k.lower():int(re.search('Numbers of '+k+r' Violated Endpoints</td>\s*<td>(\d+)',timing)[1]) for k in ('Setup','Hold')}
 assert violations=={'setup':0,'hold':0},violations
 a=timing.index('Max Frequency Summary:');table=timing[a:timing.index('</table>',a)];freq={}
 for row in re.findall(r'<tr[^>]*>(.*?)</tr>',table,re.S):
  cells=re.findall(r'<td[^>]*>(.*?)</td>',row,re.S)
  if len(cells)>=4:freq[cells[1]]=float(cells[3].replace('(MHz)',''))
 assert freq['sys_clk']>=50 and next(v for k,v in freq.items() if 'CLKOUT1' in k)>=25,freq
 pins=(pnr/(name+'.pin.html')).read_text();rows=[re.findall(r'<td[^>]*>(.*?)</td>',r,re.S) for r in re.findall(r'<tr[^>]*>(.*?)</tr>',pins,re.S)]
 expected={}
 for item in pinmap['pins']:
  if 'hand' in item:
   signal={'SCL':'imu_scl','SDA':'imu_sda','INT':'imu_int_n','RST':'imu_rst_n'}[item['signal']]+f'[{item["hand"]}]'
   expected[signal]=item['fpga_ball']
 for signal,ball in expected.items():
  row=next(r for r in rows if r and r[0].strip()==signal);assert row[2].strip()==ball+'/2' and 'LVCMOS33' in row,(signal,row)
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
 target=R/'fpga/bitstream'/(name+'.fs');fs=pnr/(name+'.fs')
 assert not target.exists() or c.sha(target)==c.sha(fs),'Do not overwrite published firmware'
 target.parent.mkdir(exist_ok=True)
 if not target.exists():shutil.copy2(fs,target)
 for directory in ('pnr','gwsynthesis'):
  dest=R/'fpga/reports/duo02'/directory;dest.mkdir(parents=True,exist_ok=True)
  for p in (W/'impl'/directory).glob(name+'*'):
   if p.suffix in ('.html','.txt'):shutil.copy2(p,dest/p.name)
 data={'project':'fpga/duo02/'+name+'.gprj','top':'top_duo02','firmware':target.relative_to(R).as_posix(),'sha256':c.sha(target),
  'version_marker':'DUO02','source_sha256':c.inputs(),'timing_violations':violations,'fmax_mhz':freq,'resources':resources,
  'physical_board_tested':False,'sram_downloaded':False,'flash_downloaded':False,'default_imu_enabled':[False,False],'default_muted':True,
  'digital_path_validation':'board-test/duo02/board-path-validation.json','ui_validation':'board-test/duo02/validation.json',
  'audio_validation':'board-test/duo02/audio-validation.json','stereo_output_validation':'board-test/duo02/stereo-output-validation.json',
  'pinmap':'board-test/duo02/pinmap.json','audio_format':'independent 16-bit stereo with switchable delay/chorus/reverb, PT8211 LSBJ 48kHz',
  'actual_dual_modules_verified':False,'analog_audio_verified':False,'motion_to_analog_latency_verified':False,
  'completed_utc':datetime.now(timezone.utc).isoformat()}
 (O/'firmware.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print(json.dumps({k:data[k] for k in ('sha256','resources','fmax_mhz')},indent=2),flush=True)
if __name__=='__main__':main()
