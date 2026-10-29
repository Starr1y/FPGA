"""Package the independent, timing-checked DUO02 mouse project."""
from pathlib import Path
import shutil,hashlib,json
BUNDLE='duo02-mouse-1.4-20261017'
def package(root,destination):
    root=Path(root);source=root/'fpga/duo02-mouse';dest=Path(destination);dest.mkdir(parents=True,exist_ok=True)
    for name in ('rtl','tb'):
        shutil.copytree(source/name,dest/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    for name in ('tanglab_duo02_mouse.gprj','tanglab_duo02_mouse.cst','tanglab_duo02_mouse.sdc','build.tcl','synthesis_only.tcl','BASELINE.json'):
        shutil.copy2(source/name,dest/name)
    config=source/'impl/tanglab_duo02_mouse_process_config.json'
    if not config.is_file():raise FileNotFoundError('Gowin IDE 配置缺失：'+str(config))
    (dest/'impl').mkdir(exist_ok=True);shutil.copy2(config,dest/'impl'/config.name)
    source_only=(source/'SOURCE_ONLY.txt').exists()
    verification=json.loads((source/'VERIFICATION.json').read_text(encoding='utf-8')) if (source/'VERIFICATION.json').exists() else {}
    if source_only:verification={}
    bit=source/'impl/pnr/tanglab_duo02_mouse.fs'
    if verification.get('timing_pass') is True:
        if verification.get('bitstream_sha256')!=hashlib.sha256(bit.read_bytes()).hexdigest():raise ValueError('位流校验值不匹配')
        shutil.copy2(bit,dest/'TangLab-DUO02-MOUSE.fs')
        shutil.copy2(source/'VERIFICATION.json',dest/'VERIFICATION.json')
    else:
        (dest/'交付状态.txt').write_text('按用户要求仅交付源码、ROM、CST/SDC、IDE配置及上位机。\n本次仅运行综合，布局布线与下载由用户执行；本目录不提供新.fs，不宣称时序或实物通过。\n打开tanglab_duo02_mouse.gprj，运行综合与布局布线。\n成功后在impl/pnr/tanglab_duo02_mouse.fs取得位流，自行使用官方Programmer下载。\nRTL与软件模拟检查已通过；实物听音、HDMI及串口待验证。\n',encoding='utf-8')
    if source_only:shutil.copy2(source/'SOURCE_ONLY.txt',dest/'交付状态.txt')
    if not source_only and (source/'SYNTHESIS_CHECK.txt').exists():shutil.copy2(source/'SYNTHESIS_CHECK.txt',dest/'SYNTHESIS_CHECK.txt')
    for stage in (('gwsynthesis','pnr') if verification.get('timing_pass') is True else ('gwsynthesis',) if not source_only and (source/'SYNTHESIS_CHECK.txt').exists() else ()):
        target=dest/'reports'/stage;target.mkdir(parents=True,exist_ok=True)
        for f in (source/'impl'/stage).iterdir():
            if f.is_file() and f.suffix in ('.html','.txt'):shutil.copy2(f,target/f.name)
    shutil.copy2(root/'鼠标音区上板测试指南.txt',dest/'鼠标音区上板测试指南.txt')
    if (root/'鼠标音区音量与延音更新说明.txt').exists():shutil.copy2(root/'鼠标音区音量与延音更新说明.txt',dest/'鼠标音区音量与延音更新说明.txt')
    files=sorted(p for p in dest.rglob('*') if p.is_file() and p.name!='SHA256.txt')
    (dest/'SHA256.txt').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(dest).as_posix() for p in files)+'\n',encoding='utf-8')
    return dest
