"""Actual mechanical input -> frame CDC -> menu rasters, 50/25MHz digital only."""
from pathlib import Path
import hashlib,json,subprocess
from PIL import Image
R=Path(__file__).resolve().parents[2];W=R/'fpga/controls_display';O=R/'board-test/menu-display'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def q(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def main():
 O.mkdir(parents=True,exist_ok=True)
 files=list((W/'rtl').glob('*.v'))+list((R/'fpga/controls/rtl').glob('*.v'))+[W/'tb/tb_menu_display_core.sv']
 inputs=files+list((W/'rtl').glob('*.hex'))+list((W/'rtl').glob('*.vh'))
 before={p.relative_to(R).as_posix():sha(p) for p in inputs}
 cmd='cd '+q(linux(W))+' && iverilog -g2012 -I. -s tb_menu_display_core -o '+q(linux(O/'menu-bridge.vvp'))+' '+' '.join(q(linux(p)) for p in files)+' && stdbuf -oL vvp '+q(linux(O/'menu-bridge.vvp'))+' +OUT='+q(linux(O))
 with (O/'bridge.log').open('wb') as log:a=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],stdout=log,stderr=subprocess.STDOUT)
 text=(O/'bridge.log').read_text(encoding='utf8',errors='replace');assert a.returncode==0 and 'TB_PASS' in text,text
 assert before=={p.relative_to(R).as_posix():sha(p) for p in inputs},'sources changed during check'
 frames={}
 for p in O.glob('linked-*.ppm'):
  image=Image.open(p);assert image.size==(640,480);pixels=image.load();visible=0
  for y in range(480):
   for x in range(640):
    if pixels[x,y] not in ((8,0,16),(10,0,20)):
     visible+=1;assert 32<=x<608 and 28<=y<438,(p.name,x,y)
  assert visible==0 if p.stem in ('linked-0','linked-3') else visible>1000,p.name
  dest=p.with_suffix('.png');image.save(dest);frames[dest.name]=sha(dest);p.unlink()
 assert len(frames)==4 and frames['linked-0.png']==frames['linked-3.png']
 assert frames['linked-1.png']!=frames['linked-2.png'],'actual edit did not alter pixels'
 data={'passed':True,'source_sha256':before,'frames_sha256':frames,'core_clock_hz':50000000,'pixel_clock_hz':25000000,
  'clocks_have_non_aligned_phase':True,'raw_mechanical_inputs':True,'parameters_from_menu_core':True,'physical_controls_verified':False,
  'physical_hdmi_verified':False,'integrated_into_duo02':False,'messages':[s for s in text.splitlines() if 'TB_PASS' in s]}
 (O/'bridge-validation.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf8');print(data['messages'],flush=True)
if __name__=='__main__':main()
