"""Standalone DUO01 check/build/verify. Never downloads SRAM or Flash."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,shutil
from PIL import Image
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo01';O=R/'board-test/duo01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inputs():return {p.relative_to(W).as_posix():sha(p) for p in W.rglob('*') if p.is_file() and 'impl' not in p.relative_to(W).parts and p.suffix in ('.v','.hex','.sv','.gprj','.cst','.sdc','.tcl','.json')}
def linux(p):return '/mnt/'+p.drive[0].lower()+str(p)[2:].replace('\\','/')
def quote(s):return "'"+str(s).replace("'","'\"'\"'")+"'"
def simulate(top,files):
 target=O/(top+'.vvp');cmd='cd '+quote(linux(W))+' && iverilog -g2012 -DTANG_SIM -s '+top+' -o '+quote(linux(target))+' '+' '.join(quote(linux(p)) for p in files)+' && vvp '+quote(linux(target))+' +OUT='+quote(linux(O))
 result=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
 output=result.stdout.decode('utf8',errors='replace');(O/(top+'.log')).write_text(output+'\n'+result.stderr.decode('utf8',errors='replace'),encoding='utf8')
 assert result.returncode==0 and 'TB_PASS' in output,output
 print(output.strip(),flush=True)
 return {'passed':True,'messages':[s for s in output.splitlines() if 'TB_PASS' in s]}
def check():
 before=inputs();O.mkdir(parents=True,exist_ok=True)
 cases={'keys':simulate('tb_duo_keys',[W/'rtl/duo_keys.v',W/'tb/tb_duo_keys.sv']),
 'panel':simulate('tb_duo_panel',[W/'rtl'/n for n in ['duo_panel.v','duo_font.v','duo_text.v','duo_fan.v','video_font.v']]+[W/'tb/tb_duo_panel.sv'])}
 frames={}
 for p in sorted(O.glob('*.ppm')):
  im=Image.open(p);assert im.size==(640,480);pix=im.load()
  for y in range(480):
   for x in range(640):
    if pix[x,y] not in ((8,0,16),(10,0,20)):
     assert 32<=x<608 and 28<=y<468,(p.name,x,y,pix[x,y])
  dest=p.with_suffix('.png');im.save(dest);frames[dest.name]=sha(dest);p.unlink()
 assert frames['duo-1.png']==frames['duo-2.png'],'hidden telemetry changed main page'
 assert frames['duo-2.png']!=frames['duo-3.png'],'diagnostic page invisible'
 assert frames['duo-1.png']!=frames['duo-4.png'],'hits not visible'
 assert before==inputs(),'sources changed during checks'
 (O/'validation.json').write_text(json.dumps({'passed':True,'source_sha256':before,'tests':cases,'frames_sha256':frames,
  'native_raster':[640,480],'telemetry_fixtures':True,'physical_hdmi_tested':False,'hidden_telemetry_invariant':True},indent=2)+'\n')
def build(executable):
 O.mkdir(parents=True,exist_ok=True);before=inputs()
 with tempfile.TemporaryDirectory(prefix='duo01-gowin-') as temporary:
  wrapper=Path(temporary)/'run.tcl';wrapper.write_text('if {[catch {source build.tcl} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/'gowin-build.log').open('w',encoding='utf8') as log:
   result=subprocess.run([executable,str(wrapper)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 assert inputs()==before,'build inputs changed'
 (O/'build-inputs.json').write_text(json.dumps(before,indent=2)+'\n')
 assert result.returncode==0,'See board-test/duo01/gowin-build.log'
 fs=W/'impl/pnr/tanglab_duo01.fs';assert fs.exists(),'Missing bitstream'
 print('Built',fs,sha(fs),flush=True)
def verify():
 data=json.loads((O/'validation.json').read_text());assert data['passed']
 for n,digest in data['source_sha256'].items():assert sha(W/n)==digest,n
 for n,digest in data['frames_sha256'].items():assert sha(O/n)==digest,n
 frozen=O/'firmware.json'
 if frozen.exists():
  release=json.loads(frozen.read_text(encoding='utf8'))
  assert sha(R/release['firmware'])==release['sha256'],'frozen bitstream'
  assert release['source_sha256']==inputs(),'frozen build inputs'
  assert release['timing_violations']=={'setup':0,'hold':0}
  for name in ('board-path-validation.json','audio-validation.json'):
   evidence=json.loads((O/name).read_text(encoding='utf8'));assert evidence['passed'],name
   for n,digest in evidence['source_sha256'].items():assert sha(R/n)==digest,(name,n)
 print('PASS DUO01 simulation inputs and raster hashes; hardware tests deferred')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('action',choices=['check','build','verify']);p.add_argument('--gowin-shell');a=p.parse_args()
 if a.action=='check':check()
 elif a.action=='verify':verify()
 else:build(a.gowin_shell or shutil.which('gw_sh') or 'D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe')
