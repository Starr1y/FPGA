"""Repeatable portable release packaging. Does not build/program FPGA."""
import argparse,hashlib,shutil,subprocess,sys,zipfile
from pathlib import Path
SRC=Path(__file__).resolve().parent

def package(dest):
    shutil.copytree(SRC/'release_assets',dest,dirs_exist_ok=True)
    source=dest/'source';source.mkdir(exist_ok=True)
    for f in SRC.glob('*.py'):shutil.copy2(f,source/f.name)
    for folder in ('tests','score_assets','release_assets'):
        shutil.copytree(SRC/folder,source/folder,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    shutil.copy2(SRC/'requirements-lock.txt',source/'requirements-lock.txt')
    manifest=dest/'SHA256SUMS.txt'
    files=sorted(f for f in dest.rglob('*') if f.is_file() and f!=manifest)
    manifest.write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.relative_to(dest).as_posix()+'\n' for f in files),encoding='utf-8')
    archive=dest.parent/(dest.name+'-分享包.zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for f in [*files,manifest]:z.write(f,dest.name+'/'+f.relative_to(dest).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:raise RuntimeError('分享包CRC校验失败')
    print('PORTABLE',dest/'TangLab.exe');print('ZIP',archive)

def main():
    p=argparse.ArgumentParser(description='构建与打包TangLab2.7.2（不操作FPGA）');p.add_argument('--output',type=Path,required=True);p.add_argument('--work',type=Path);p.add_argument('--build',action='store_true');a=p.parse_args()
    if a.build:
        if not a.work:p.error('--build需要指定--work临时构建目录')
        subprocess.run([sys.executable,str(SRC/'build_gesture24.py'),'--output',str(a.output),'--work',str(a.work)],check=True)
    if not (a.output/'TangLab.exe').is_file():p.error('输出目录没有TangLab.exe，请先构建或添加--build')
    package(a.output)
if __name__=='__main__':main()
