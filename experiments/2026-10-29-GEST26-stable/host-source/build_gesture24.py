"""Rebuild Windows GUI; FPGA compilation is separate and never flashed."""
from pathlib import Path
import sys,os,subprocess,shutil,argparse
SRC=Path(__file__).resolve().parent
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--work',type=Path,required=True);a=ap.parse_args()
    from PySide6.QtCore import QLibraryInfo
    translation=Path(QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath))/'qtbase_zh_CN.qm'
    work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
    command=[sys.executable,'-m','PyInstaller','--noconfirm','--windowed','--onedir','--name','TangLab','--distpath',str(work/'dist'),'--workpath',str(work/'build'),'--specpath',str(work),'--hidden-import','serial.tools.list_ports_windows','--add-data',str(translation)+';PySide6/translations']
    for name in ('matplotlib','scipy','pandas','torch','tensorflow','cv2','IPython','notebook','pytest','tkinter','PyQt5','PyQt6','PySide2'):command+=['--exclude-module',name]
    subprocess.run(command+[str(SRC/'tanglab.py')],cwd=SRC,check=True)
    a.output.mkdir(parents=True,exist_ok=True);shutil.copytree(work/'dist/TangLab',a.output,dirs_exist_ok=True)
    for name in ('icuuc.dll','icudt78.dll'):(a.output/'_internal'/name).unlink(missing_ok=True)
    for dll in (a.output/'_internal/PySide6').glob('MSVCP140*.dll'):shutil.copy2(dll,a.output/'_internal'/dll.name)
    subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--onefile','--console','--name','TangLabCtl','--distpath',str(a.output),'--workpath',str(work/'cli-build'),'--specpath',str(work),str(SRC/'tanglabctl.py')],cwd=SRC,check=True)
    print('EXE_BUILD_COMPLETE',a.output)
if __name__=='__main__':main()
