"""Capture real UI RTL for both pages, including hidden telemetry invariance."""
from pathlib import Path
import subprocess, json, hashlib
from PIL import Image
R=Path(__file__).resolve().parents[2];W=R/'fpga/i2cfan04';O=R/'board-test/i2c-fan04'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def wsl(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def main():
 files=[W/'rtl'/n for n in ('video_instrument_panel.v','video_font.v','video_font_zh.v','video_text_zh.v','video_fan_map.v','fan_spans.hex')]+[W/'tb/tb_ui_render.sv']
 before={p.relative_to(R).as_posix():sha(p) for p in files};O.mkdir(parents=True,exist_ok=True)
 cmd='cd "'+wsl(W)+'" && iverilog -g2012 -s tb_ui_render -o /tmp/tanglab-fan04-render '+' '.join('"'+wsl(p)+'"' for p in files if p.suffix!='.hex')+' && vvp /tmp/tanglab-fan04-render +OUT='+wsl(O)
 r=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 s=r.stdout.decode('utf8',errors='replace');(O/'render.log').write_text(s+'\n'+r.stderr.decode('utf8',errors='replace'),encoding='utf8')
 assert r.returncode==0 and 'TB_PASS' in s,s
 frames={}
 for page in range(2):
  for state in range(17):
   p=O/f'ui-page-{page}-state-{state}.ppm';im=Image.open(p);pixels=im.load()
   for y in range(480):
    for x in range(640):
     bg=(8,0,16) if y%4==0 else (10,0,20)
     if pixels[x,y]!=bg:assert 32<=x<=607 and 24<=y<458,(page,state,x,y)
   dest=p.with_suffix('.png');im.save(dest);frames[dest.name]=sha(dest);p.unlink()
 # Primary frames must be identical when only hidden numeric telemetry changes.
 assert frames['ui-page-0-state-2.png']==frames['ui-page-0-state-9.png'],'hidden diagnostics leaked into primary page'
 assert frames['ui-page-1-state-2.png']!=frames['ui-page-1-state-9.png'],'diagnostics did not show measured updates'
 assert before=={p.relative_to(R).as_posix():sha(p) for p in files}
 data={'passed':True,'source_sha256':before,'frames_sha256':frames,'pages':['performance','diagnostics'],
       'states':['disabled','configuring','ready','hit','F03','low_accuracy','moving','calibration_timeout','calibrating','changed_hidden_telemetry','release_confirmation'],
       'hidden_telemetry_pixel_invariance':True,'fixture_telemetry_only':True,'native':[640,480],
       'version_marker':'I2C250K / FAN04','physical_hdmi_tested':False}
 (O/'render-validation.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print('TB_PASS 34 actual RTL rasters, page isolation and overscan bounds; fixture values are simulated',flush=True)
if __name__=='__main__':main()
