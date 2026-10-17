"""Build/verify DUO03. Never downloads SRAM or Flash, never edits old releases."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,shutil
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo03';O=R/'board-test/duo03'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inputs():
 # HDL testbenches are covered by their own execution manifests. They are not
 # consumed by Gowin; editing a bench cannot silently invalidate a live build.
 return {p.relative_to(W).as_posix():sha(p) for p in W.rglob('*') if p.is_file() and 'impl' not in p.relative_to(W).parts and p.suffix in ('.v','.hex','.vh','.gprj','.cst','.sdc','.tcl','.json')}
def verify():
 names=('tb_duo_controls-validation.json','video-validation.json','audio-validation.json','board-path-validation.json','board-video-validation.json','build-validation.json')
 for name in names:
  data=json.loads((O/name).read_text(encoding='utf8'));assert data['passed'],name
  for n,d in data['source_sha256'].items():assert sha(R/n)==d,(name,n)
  for n,d in data.get('frames_sha256',{}).items():assert sha(O/n)==d,(name,n)
  for n,d in data.get('report_sha256',{}).items():assert sha(R/n)==d,(name,n)
 for n in ('note-map','synth-8','synth-32'):
  data=json.loads((O/'audio-validation.json').read_text(encoding='utf8'));assert data['tests'][n]['passed'],n
 if (O/'firmware.json').exists():
  data=json.loads((O/'firmware.json').read_text(encoding='utf8'))
  assert data['source_sha256']==inputs(),'frozen hardware input set/bytes changed'
  assert sha(R/data['firmware'])==data['sha256'],'frozen FS changed'
  assert data['timing_violations']=={'setup':0,'hold':0}
 print('PASS DUO03 checked digital source/frame evidence; physical tests deferred',flush=True)
def build(executable):
 O.mkdir(parents=True,exist_ok=True);before=inputs()
 with tempfile.TemporaryDirectory(prefix='duo03-gowin-') as temporary:
  t=Path(temporary)/'run.tcl';t.write_text('if {[catch {source build.tcl} error]} {puts stderr $error;exit 1}\nexit 0\n')
  with (O/'gowin-build.log').open('w',encoding='utf8') as log:
   child=subprocess.Popen([executable,str(t)],cwd=W,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
   print('DUO03 Gowin process',child.pid,flush=True);code=child.wait()
 assert inputs()==before,'hardware source changed during build'
 (O/'build-inputs.json').write_text(json.dumps(before,indent=2)+'\n',encoding='utf8')
 assert code==0,'Gowin failed; inspect the existing log, do not restart on an observation timeout'
 fs=W/'impl/pnr/tanglab_duo03.fs';assert fs.exists(),'missing bitstream'
 print('Built DUO03',sha(fs),flush=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('action',choices=('build','verify'));p.add_argument('--gowin-shell');a=p.parse_args()
 if a.action=='verify':verify()
 else:build(a.gowin_shell or shutil.which('gw_sh') or 'D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe')
