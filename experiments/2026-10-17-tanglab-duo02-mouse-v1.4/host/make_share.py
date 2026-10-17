"""Create a clean portable ZIP from build_exe.py --package-only output."""
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
import sys

def package(source,target):
    source=Path(source);target=Path(target)
    allowed={'TangLab.exe','TangLabCtl.exe','_internal','licenses','source','fpga','docs','board-test','使用说明.txt',
             '两声部与SPI上板测试指南.txt','钢琴音色使用说明.txt','piano-tail-fix-20261008','使用说明.md','THIRD_PARTY_NOTICES.md','requirements-lock.txt',
             '鼠标音区上板测试指南.txt','鼠标音区音量与延音更新说明.txt','duo02-mouse-1.4-20261017'}
    required=['TangLab.exe','TangLabCtl.exe','_internal','licenses','source/tanglab.py','source/lab_ui.py',
              'fpga/bitstream/tanglab.fs','使用说明.txt']
    for name in required:
        if not (source/name).exists():raise ValueError('交付文件缺失：'+name)
    with ZipFile(target,'w',ZIP_DEFLATED,compresslevel=6) as archive:
        for p in sorted(source.rglob('*')):
            rel=p.relative_to(source)
            if not p.is_file() or rel.parts[0] not in allowed:continue
            if any(x in ('recordings','__pycache__','.venv') for x in rel.parts):continue
            if 'impl' in rel.parts and p.name not in ('tanglab_process_config.json','tanglab_duo02_mouse_process_config.json'):continue
            if p.suffix.lower() in ('.lic','.pyc','.log'):continue
            archive.write(p,Path('TangLab')/rel)
    with ZipFile(target) as archive:
        if archive.testzip():raise ValueError('压缩包校验失败')
        print(f'分享包已校验：{target}，共 {len(archive.namelist())} 项')
if __name__=='__main__':package(sys.argv[1],sys.argv[2])
