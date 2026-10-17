"""Full top raw control to RGB check, no vendor PLL/TMDS/physical board proof."""
from pathlib import Path
import json,subprocess
from PIL import Image
from check_duo03_controls import R,W,O,sha,linux,q
def main():
 files=sorted((W/'rtl').glob('*.v'))+[W/'tb/tb_duo_board_video.sv'];inputs=files+list((W/'rtl').glob('*.hex'))+list((W/'rtl').glob('*.vh'))
 before={p.relative_to(R).as_posix():sha(p) for p in inputs};O.mkdir(parents=True,exist_ok=True)
 top='tb_duo_board_video';cmd='cd '+q(linux(W))+' && iverilog -g2012 -DTANG_VIDEO_SIM -s '+top+' -o '+q(linux(O/(top+'.vvp')))+' '+' '.join(q(linux(p)) for p in files)+' && vvp '+q(linux(O/(top+'.vvp')))+' +OUT='+q(linux(O))
 a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True);text=(a.stdout+a.stderr).decode('utf8',errors='replace');(O/'board-video.log').write_text(text,encoding='utf8')
 assert a.returncode==0 and 'TB_PASS' in text and 'ERROR:' not in text,text
 assert before=={p.relative_to(R).as_posix():sha(p) for p in inputs},'board sources changed during check'
 frames={}
 for p in sorted(O.glob('board-page-*.ppm')):
  im=Image.open(p);assert im.size==(640,480);pix=im.load()
  for y in range(480):
   for x in range(640):
    if pix[x,y] not in ((8,0,16),(10,0,20)):assert 32<=x<608 and 28<=y<468,(p.name,x,y)
  dest=p.with_suffix('.png');im.save(dest);frames[dest.name]=sha(dest);p.unlink()
 assert len(frames)==5 and frames['board-page-1.png']!=frames['board-page-2.png']
 assert frames['board-page-0.png']!=frames['board-page-4.png']
 (O/'board-video-validation.json').write_text(json.dumps({'passed':True,'source_sha256':before,'frames_sha256':frames,
  'messages':[s for s in text.splitlines() if 'TB_PASS' in s],'forced_control_state':False,'key_durations_shortened':True,
  'core_hz':50000000,'pixel_hz':25000000,'sensor_reports_simulated':False,'imu_remains_disabled':True,
  'physical_controls_tested':False,'physical_hdmi_tested':False,'vendor_pll_and_tmds_simulated':False},indent=2)+'\n',encoding='utf8')
 print('TB_PASS DUO03 raw board control to RGB; five frames',flush=True)
if __name__=='__main__':main()
