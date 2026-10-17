"""Real board video adapter with digital pixel-clock shim; no physical HDMI."""
from pathlib import Path
import json,subprocess
from PIL import Image
from check_duo03_controls import R,W,O,sha,linux,q
def main():
 O.mkdir(parents=True,exist_ok=True)
 names=['video_duo03_hdmi.v','video_status_cdc.v','duo_page_mux.v','duo_panel.v','duo_font.v','duo_text.v','duo_fan.v','video_font.v','duo_menu_panel.v','menu_font.v','menu_ascii.v','menu_labels.v']
 files=[W/'rtl'/n for n in names]+[W/'tb/tb_duo_video.sv',W/'tb/tb_duo_wet.sv']
 inputs=files+list((W/'rtl').glob('*.hex'))+list((W/'rtl').glob('*.vh'));before={p.relative_to(R).as_posix():sha(p) for p in inputs};tests={}
 for top in ('tb_duo_wet','tb_duo_video'):
  cmd='cd '+q(linux(W))+' && iverilog -g2012 -DTANG_VIDEO_SIM -s '+top+' -o '+q(linux(O/(top+'.vvp')))+' '+' '.join(q(linux(p)) for p in files)+' && vvp '+q(linux(O/(top+'.vvp')))+' +OUT='+q(linux(O))
  a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True);text=(a.stdout+a.stderr).decode('utf8',errors='replace');(O/(top+'.log')).write_text(text,encoding='utf8')
  assert a.returncode==0 and 'TB_PASS' in text and 'ERROR:' not in text,text
  tests[top]=[s for s in text.splitlines() if 'TB_PASS' in s];print(tests[top],flush=True)
 frames={}
 for p in sorted(O.glob('page-*.ppm')):
  im=Image.open(p);assert im.size==(640,480);pix=im.load()
  for y in range(480):
   for x in range(640):
    if pix[x,y] not in ((8,0,16),(10,0,20)):assert 32<=x<608 and 28<=y<468,(p.name,x,y)
  dest=p.with_suffix('.png');im.save(dest);frames[dest.name]=sha(dest);p.unlink()
 assert len(frames)==8 and frames['page-5.png']==frames['page-6.png'],'hidden telemetry changes performance view'
 assert frames['page-2.png']!=frames['page-3.png'],'actual transition is not visible'
 assert frames['page-0.png']!=frames['page-1.png'],'diagnostics did not render'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in inputs}
 (O/'video-validation.json').write_text(json.dumps({'passed':True,'source_sha256':before,'frames_sha256':frames,'tests':tests,
  'clock_hz':50000000,'pixel_hz':25000000,'vendor_pll_and_tmds_simulated':False,'native_resolution':[640,480],'physical_hdmi_tested':False},indent=2)+'\n',encoding='utf8')
if __name__=='__main__':main()
