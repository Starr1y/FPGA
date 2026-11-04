"""Build only Windows software and package the 2.1 SOURCE project. Never invokes EDA."""
from pathlib import Path
import os,sys,subprocess,shutil,argparse,hashlib
SRC=Path(__file__).resolve().parent
DATA=SRC if (SRC/'fpga').is_dir() else SRC.parent
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,default=DATA/'dist/TangLab-交互2.1');args=ap.parse_args()
    work=Path(os.environ.get('TANGLAB_BUILD_DIR',str(SRC/'build-cache-ui21')));work.mkdir(parents=True,exist_ok=True)
    from PySide6.QtCore import QLibraryInfo
    translation=Path(QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath))/'qtbase_zh_CN.qm'
    cmd=[sys.executable,'-m','PyInstaller','--noconfirm','--windowed','--onedir','--name','TangLab',
         '--distpath',str(work/'staging'),'--workpath',str(work/'build'),'--specpath',str(work),
         '--hidden-import','serial.tools.list_ports_windows','--add-data',str(translation)+';PySide6/translations']
    for name in ('matplotlib','scipy','pandas','torch','tensorflow','cv2','IPython','notebook','pytest','tkinter','PyQt5','PyQt6','PySide2'):cmd+=['--exclude-module',name]
    subprocess.run(cmd+[str(SRC/'tanglab.py')],cwd=SRC,check=True)
    dest=args.output;dest.mkdir(parents=True,exist_ok=True)
    shutil.copytree(work/'staging/TangLab',dest,dirs_exist_ok=True)
    # Known Poppler ICU ABI collision: exclude build-PATH DLLs from THIS new output.
    for name in ('icuuc.dll','icudt78.dll'):(dest/'_internal'/name).unlink(missing_ok=True)
    for dll in (dest/'_internal/PySide6').glob('MSVCP140*.dll'):shutil.copy2(dll,dest/'_internal'/dll.name)
    cli=next((p for p in (DATA/'TangLabCtl.exe',DATA/'dist/TangLab/TangLabCtl.exe') if p.is_file()),None)
    if cli is None:
        subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--onefile','--console','--name','TangLabCtl','--distpath',str(work/'cli'),'--workpath',str(work/'cli-build'),'--specpath',str(work),str(SRC/'tanglabctl.py')],cwd=SRC,check=True)
        cli=work/'cli/TangLabCtl.exe'
    shutil.copy2(cli,dest/'TangLabCtl.exe')
    license_dir=next((p for p in (DATA/'licenses',DATA/'dist/TangLab/licenses') if p.is_dir()),None)
    if license_dir is None:raise RuntimeError('缺少依赖许可目录，不能制作分享包')
    shutil.copytree(license_dir,dest/'licenses',dirs_exist_ok=True)
    for name in ('使用说明.txt','使用说明.md','THIRD_PARTY_NOTICES.md','requirements-lock.txt','按键编码器与教学操作指南.txt'):
        p=DATA/name
        if p.is_file():shutil.copy2(p,dest/name)
    docs=dest/'docs';docs.mkdir(exist_ok=True)
    for p in (DATA/'docs').glob('*'):
        if p.is_file() and p.suffix in ('.md','.txt'):shutil.copy2(p,docs/p.name)
    if (DATA/'examples').is_dir():shutil.copytree(DATA/'examples',dest/'examples',dirs_exist_ok=True)
    project=DATA/'fpga/duo04-ui21';target=dest/'fpga/duo04-ui21'
    shutil.copytree(project,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('impl','__pycache__','*.user','*.fs','*.vg','*.lic'))
    config=project/'impl/tanglab_duo04_process_config.json'
    (target/'impl').mkdir(exist_ok=True);shutil.copy2(config,target/'impl'/config.name)
    source=dest/'source';source.mkdir(exist_ok=True)
    for p in SRC.glob('*.py'):shutil.copy2(p,source/p.name)
    shutil.copytree(SRC/'tests',source/'tests',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy2(SRC/'requirements-lock.txt',source/'requirements-lock.txt')
    print('PORTABLE='+str(dest/'TangLab.exe'))
if __name__=='__main__':main()
