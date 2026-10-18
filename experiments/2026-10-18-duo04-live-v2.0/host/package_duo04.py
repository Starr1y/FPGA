"""Freeze independent DUO04 sources and explicitly validated implementation files."""
from pathlib import Path
import shutil,hashlib,json
BUNDLE='duo04-live-2.0-20261018'
def package(root,destination):
    src=Path(root)/'fpga/duo04';dst=Path(destination);dst.mkdir(parents=True,exist_ok=True)
    status=json.loads((src/'BUILD_STATUS.json').read_text(encoding='utf-8'))
    bit=src/'impl/pnr/tanglab_duo04.fs'
    if not bit.is_file():bit=src/'bitstream/tanglab_duo04.fs'
    verified=status.get('bitstream_supplied') is True and status.get('timing')=='PASS_REPORTED_PATHS' and bit.is_file() and status.get('bitstream_sha256')==hashlib.sha256(bit.read_bytes()).hexdigest()
    for p in src.rglob('*'):
        if not p.is_file() or '__pycache__' in p.parts or p.suffix in ('.pyc','.user','.bin','.binx'):continue
        rel=p.relative_to(src)
        if p.suffix=='.fs' and (p!=bit or not verified):continue
        if 'impl' in rel.parts and p.name!='tanglab_duo04_process_config.json' and p!=bit:continue
        target=dst/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    (dst/'SHA256.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(dst).as_posix()+'\n' for p in sorted(dst.rglob('*')) if p.is_file() and p.name!='SHA256.txt'),encoding='utf-8')
    return dst
