"""Freeze FAN04 only when tests, source hashes, render, pins and timing pass."""
from pathlib import Path
import hashlib,json,re,shutil
from datetime import datetime,timezone
import fan04_release as c
R,W,O=c.ROOT,c.WORK,c.OUT
def read(p):return json.loads(p.read_text(encoding='utf8'))
def main():
 sim=read(O/'simulation.json');assert set(sim)==set(c.TESTS) and all(v['passed'] for v in sim.values())
 tested=read(O/'simulation-inputs.json');assert tested['inputs_unchanged']
 assert all(c.sha(W/n)==h for n,h in tested['source_sha256'].items())
 built=read(O/'build-inputs.json');assert all(c.sha(W/n)==h for n,h in built.items())
 baseline=read(R/'board-test/i2c-fan04/baseline.json')
 assert all(c.sha(R/'fpga/i2cfan03'/n)==h for n,h in baseline['parent_sources'].items())
 assert all(c.sha(R/'fpga/bitstream'/n)==h for n,h in baseline['published_sha256'].items())
 render=read(R/'board-test/i2c-fan04/render-validation.json');assert render['passed'] and len(render['frames_sha256'])==34
 assert all(c.sha(R/n)==h for n,h in render['source_sha256'].items())
 assert all(c.sha(R/'board-test/i2c-fan04'/n)==h for n,h in render['frames_sha256'].items())
 log=(O/'gowin-build.log').read_text(encoding='utf8')
 assert 'Bitstream generation completed' in log and 'Current top module is "top_i2c_fan04"' in log
 assert not re.search(r'^ERROR\b',log,re.M)
 name='tanglab_i2c_fan04';pnr=W/'impl/pnr'
 timing=(pnr/(name+'_tr_content.html')).read_text()
 violated={k.lower():int(re.search('Numbers of '+k+r' Violated Endpoints</td>\s*<td>(\d+)',timing)[1]) for k in ('Setup','Hold')}
 assert violated=={'setup':0,'hold':0},violated
 start=timing.index('Max Frequency Summary:');table=timing[start:timing.index('</table>',start)];freq={}
 for row in re.findall(r'<tr[^>]*>(.*?)</tr>',table,re.S):
  cells=re.findall(r'<td[^>]*>(.*?)</td>',row,re.S)
  if len(cells)>=4:freq[cells[1]]=float(cells[3].replace('(MHz)',''))
 assert freq['sys_clk']>=50 and next(v for k,v in freq.items() if 'CLKOUT1' in k)>=25,freq
 pins=(pnr/(name+'.pin.html')).read_text();expected={'imu_data':'C18','imu_clk_tx':'E19','imu_int_n':'E16','imu_rst_n':'D20'}
 rows=[re.findall(r'<td[^>]*>(.*?)</td>',r,re.S) for r in re.findall(r'<tr[^>]*>(.*?)</tr>',pins,re.S)]
 for signal,pin in expected.items():
  row=next(r for r in rows if r and r[0].strip()==signal)
  assert row[2].strip()==pin+'/2' and 'LVCMOS33' in row,(signal,row)
  if signal in ('imu_data','imu_clk_tx'):assert row[4].strip()=='io',row
 vg=(W/'impl/gwsynthesis'/(name+'.vg')).read_text()
 for signal in ('imu_data','imu_clk_tx','imu_rst_n'):
  primitive='TBUF' if signal=='imu_rst_n' else 'IOBUF';pad='O' if signal=='imu_rst_n' else 'IO'
  blocks=re.findall(primitive+r'\s+\w+\s*\([^;]*?\);',vg,re.S)
  block=next(b for b in blocks if '.'+pad+'('+signal+')' in b)
  assert re.search(r"\.I\((?:GND|1'b0)\)",block),block
 resources={};report=(pnr/(name+'.rpt.txt')).read_text()
 for key in ('Logic','Register','BSRAM','DSP'):
  m=re.search(r'^\s*'+key+r'\s*\|\s*([\d.]+)/([\d.]+)',report,re.M);assert m,key
  resources[key]={'used':float(m[1]),'available':float(m[2])}
 source={p.relative_to(W).as_posix():c.sha(p) for p in W.rglob('*') if p.is_file() and 'impl' not in p.relative_to(W).parts and p.suffix in ('.v','.sv','.hex','.cst','.sdc','.gprj','.tcl')}
 target=R/'fpga/bitstream'/(name+'.fs');fs=pnr/(name+'.fs')
 assert not target.exists() or c.sha(target)==c.sha(fs),'Preserve published artifact'
 if not target.exists():shutil.copy2(fs,target)
 evidence=R/'board-test/i2c-fan04'
 for p in O.iterdir():
  if p.suffix in ('.log','.json'):shutil.copy2(p,evidence/p.name)
 for directory in ('pnr','gwsynthesis'):
  dest=R/'fpga/reports/i2c-fan04'/directory;dest.mkdir(parents=True,exist_ok=True)
  for p in (W/'impl'/directory).glob(name+'*'):
   if p.suffix in ('.html','.txt'):shutil.copy2(p,dest/p.name)
 parent=read(R/'board-test/I2C负Z独立加速度或急动度固件清单.json')
 data={k:v for k,v in parent.items() if k not in ('source_sha256','timestamp_source_comparison')}
 data.update(firmware=target.relative_to(R).as_posix(),project='fpga/i2cfan04/'+name+'.gprj',top='top_i2c_fan04',version_marker='FAN04',sha256=c.sha(target),bytes=target.stat().st_size,
  source_sha256=source,simulations=sim,render_validation=render,timing_violations=violated,fmax_mhz=freq,resources=resources,pins=expected,
  pose_report_hz=100,expression_filter_pose_hz=100,expression_report_dt_ticks=[95,105],expression_report_tick_us=100,
  expression_silence_timeout_ms=50,expression_sequence_and_timestamp_admission=True,
  expression_bend_limit_cents=200,expression_vibrato_limit_cents=30,expression_vibrato_band_hz=[3,10],
  common_test_sha256={'fpga/tb/tb_video_hdmi.sv':c.sha(R/'fpga/tb/tb_video_hdmi.sv')},
  physical_expression_verified=False,sram_downloaded=False,flash_downloaded=False,
  inherited_FAN03_production_path_evidence='board-test/i2c-fan03/tb_i2c_path.log',
  production_path_rerun=False,completed_utc=datetime.now(timezone.utc).isoformat())
 c.MANIFEST.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print(json.dumps({k:data[k] for k in ('sha256','resources','fmax_mhz')},indent=2),flush=True)
if __name__=='__main__':main()
