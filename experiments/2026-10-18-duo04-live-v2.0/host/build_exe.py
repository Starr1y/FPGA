"""Build a portable Windows folder. Run with the project venv Python."""
import subprocess,sys,shutil,json,importlib.metadata,os
from pathlib import Path
ROOT=Path(__file__).resolve().parent
WORK=Path(os.environ.get('TANGLAB_BUILD_DIR',str(ROOT/'build-cache')))
def main():
    WORK.mkdir(parents=True,exist_ok=True)
    out=ROOT/'dist'
    from PySide6.QtCore import QLibraryInfo
    translation=Path(QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath))/'qtbase_zh_CN.qm'
    args=[sys.executable,'-m','PyInstaller','--noconfirm','--windowed','--onedir','--name','TangLab',
          '--distpath',str(WORK/'staging'),'--workpath',str(WORK/'build'),'--specpath',str(WORK),
          '--hidden-import','serial.tools.list_ports_windows',
          '--add-data',str(translation)+';PySide6/translations']
    for name in ('matplotlib','scipy','pandas','torch','tensorflow','cv2','IPython','notebook','pytest','tkinter','PyQt5','PyQt6','PySide2'):
        args+=['--exclude-module',name]
    subprocess.run(args+[str(ROOT/'tanglab.py')],cwd=ROOT,check=True)
    subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--onefile','--console','--name','TangLabCtl',
                    '--distpath',str(WORK/'cli'),'--workpath',str(WORK/'cli-build'),'--specpath',str(WORK),
                    str(ROOT/'tanglabctl.py')],cwd=ROOT,check=True)
    dest=WORK/'release/TangLab' if '--package-only' in sys.argv else out/'TangLab'
    shutil.copytree(WORK/'staging/TangLab',dest,dirs_exist_ok=True)
    shutil.copy2(WORK/'cli/TangLabCtl.exe',dest/'TangLabCtl.exe')
    # Qt uses the Windows system ICU ABI. Poppler's same-name DLL uses a
    # different ABI and can be picked up from the build process PATH.
    for name in ('icuuc.dll','icudt78.dll'):
        (dest/'_internal'/name).unlink(missing_ok=True)
    for dll in (dest/'_internal/PySide6').glob('MSVCP140*.dll'):
        shutil.copy2(dll,dest/'_internal'/dll.name)
    for package in ('PySide6','PySide6_Essentials','PySide6_Addons','shiboken6','pyqtgraph','pyserial','numpy','pyinstaller'):
        dist=importlib.metadata.distribution(package)
        for entry in dist.files or []:
            if any(word in str(entry).lower() for word in ('license','copying','copyright','notice')):
                src=Path(dist.locate_file(entry))
                if src.is_file():
                    target=dest/'licenses'/package/str(entry).replace('../','')
                    target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    for name in ['使用说明.txt','使用说明.md','THIRD_PARTY_NOTICES.md','requirements-lock.txt']:
        shutil.copy2(ROOT/name,dest/name)
    shutil.copytree(ROOT/'docs',dest/'docs',dirs_exist_ok=True)
    if (ROOT/'board-test').is_dir():shutil.copytree(ROOT/'board-test',dest/'board-test',dirs_exist_ok=True)
    for p in ROOT.glob('*指南.txt'):shutil.copy2(p,dest/p.name)
    for p in ROOT.glob('*说明.txt'):shutil.copy2(p,dest/p.name)
    shutil.copytree(ROOT/'fpga',dest/'fpga',dirs_exist_ok=True,ignore=shutil.ignore_patterns('impl','__pycache__','*.user'))
    # Gowin stores persistent IDE options in impl, alongside generated files.
    # Preserve this configuration even though build intermediates are excluded.
    config=ROOT/'fpga/impl/tanglab_process_config.json'
    if config.is_file():
        (dest/'fpga/impl').mkdir(parents=True,exist_ok=True)
        shutil.copy2(config,dest/'fpga/impl'/config.name)
    source=dest/'source';source.mkdir(exist_ok=True)
    for p in ROOT.glob('*.py'):shutil.copy2(p,source/p.name)
    shutil.copytree(ROOT/'tests',source/'tests',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy2(ROOT/'requirements-lock.txt',source/'requirements-lock.txt')
    bit=ROOT/'fpga/impl/pnr/tanglab.fs'
    if bit.is_file():
        (dest/'fpga/bitstream').mkdir(exist_ok=True)
        target=dest/'fpga/bitstream/tanglab.fs'
        if target.exists():target.chmod(0o666)
        shutil.copy2(bit,target)
    for folder in ('gwsynthesis','pnr'):
        target=dest/'fpga/reports'/folder;target.mkdir(parents=True,exist_ok=True)
        for p in (ROOT/'fpga/impl'/folder).glob('*'):
            if p.suffix in ('.html','.txt'):shutil.copy2(p,target/p.name)
    if bit.is_file():
        from package_firmware import package,BUNDLE
        package(ROOT,dest/BUNDLE)
    if (ROOT/'fpga/duo02-mouse/tanglab_duo02_mouse.gprj').exists():
        from package_duo import package,BUNDLE
        package(ROOT,dest/BUNDLE)
    if (ROOT/'fpga/duo04/tanglab_duo04.gprj').exists():
        from package_duo04 import package,BUNDLE
        package(ROOT,dest/BUNDLE)
        package(ROOT,dest/'fpga/duo04')
    print('PORTABLE='+str(dest/'TangLab.exe'))
if __name__=='__main__':main()
