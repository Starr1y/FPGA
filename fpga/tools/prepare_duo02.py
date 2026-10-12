"""One-time DUO02 snapshot. Never edits frozen DUO01, downloads, or reruns setup."""
from pathlib import Path
import shutil,hashlib,json
R=Path(__file__).resolve().parents[2];S=R/'fpga/duo01';W=R/'fpga/duo02'
assert not W.exists(),'DUO02 already exists; edit its RTL instead of reinitializing it'
sources={}
for p in S.rglob('*'):
 if p.is_file() and 'impl' not in p.relative_to(S).parts and not p.name.endswith('.gprj.user'):
  dest=W/p.relative_to(S);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
  sources[p.relative_to(R).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
for old,new in [('tanglab_duo01.gprj','tanglab_duo02.gprj'),('tanglab_duo01.cst','tanglab_duo02.cst'),('tanglab_duo01.sdc','tanglab_duo02.sdc'),('rtl/top_duo01.v','rtl/top_duo02.v')]:
 (W/old).rename(W/new)
for p in [W/'tanglab_duo02.gprj',W/'build.tcl',W/'rtl/top_duo02.v']:
 p.write_text(p.read_text(encoding='utf8').replace('duo01','duo02'),encoding='utf8')
for name in ('stereo_fx.v',):
 p=R/'fpga/effects/rtl'/name;shutil.copy2(p,W/'rtl'/name);sources[p.relative_to(R).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
(W/'dependency-sources.json').write_text(json.dumps(sources,indent=2)+'\n',encoding='utf8')
print('Prepared DUO02 snapshot; frozen DUO01 untouched')
