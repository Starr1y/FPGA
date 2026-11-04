"""Rebuild Windows GUI; FPGA compilation is separate and never flashed."""
from pathlib import Path
import sys,os,subprocess,shutil,argparse,ssl
SRC=Path(__file__).resolve().parent
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--work',type=Path,required=True);a=ap.parse_args()
    from PySide6.QtCore import QLibraryInfo
    translation=Path(QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath))/'qtbase_zh_CN.qm'
    work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
    command=[sys.executable,'-m','PyInstaller','--noconfirm','--windowed','--onedir','--name','TangLab','--distpath',str(work/'dist'),'--workpath',str(work/'build'),'--specpath',str(work),'--hidden-import','serial.tools.list_ports_windows','--add-data',str(SRC/'score_assets')+';score_assets','--add-data',str(translation)+';PySide6/translations']
    for name in ('matplotlib','scipy','pandas','torch','tensorflow','cv2','IPython','notebook','pytest','tkinter','PyQt5','PyQt6','PySide2'):command+=['--exclude-module',name]
    command+=['--add-data',str(SRC/'theme_assets')+';theme_assets']
    subprocess.run(command+[str(SRC/'lite29.py')],cwd=SRC,check=True)
    a.output.mkdir(parents=True,exist_ok=True);shutil.copytree(work/'dist/TangLab',a.output,dirs_exist_ok=True)
    for name in ('icuuc.dll','icudt78.dll'):(a.output/'_internal'/name).unlink(missing_ok=True)
    # Native Poppler on the build host ships incompatible same-name OpenSSL
    # DLLs. urllib/_ssl must use the matched Python runtime pair.
    for name in ('libssl-3-x64.dll','libcrypto-3-x64.dll'):
        runtime=Path(sys.base_prefix)/'DLLs'/name
        if not runtime.is_file():raise RuntimeError('Missing Python TLS runtime: '+str(runtime))
        shutil.copy2(runtime,a.output/'_internal'/name)
    # This bundled Python distribution references an adjacent public CA file
    # from SSLContext.__new__. Preserve it in the frozen ssl module's directory.
    trust=Path(ssl.__file__).with_name('codex-rejected-cas.pem')
    if trust.is_file():shutil.copy2(trust,a.output/'_internal'/trust.name)
    for dll in (a.output/'_internal/PySide6').glob('MSVCP140*.dll'):shutil.copy2(dll,a.output/'_internal'/dll.name)
    print('EXE_BUILD_COMPLETE',a.output)
if __name__=='__main__':main()
