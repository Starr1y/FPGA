"""Keep the current Gowin project, reusable IDE options and bitstream together."""
import hashlib,shutil,sys
from pathlib import Path

BUNDLE='piano-tail-fix-20261008'
def package(root,destination):
    root=Path(root);source=root/'fpga';destination=Path(destination)
    destination.mkdir(parents=True,exist_ok=True)
    for name in ('rtl','tb'):
        shutil.copytree(source/name,destination/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    for name in ('tanglab.gprj','tanglab.cst','tanglab.sdc','build.tcl','run_sim.py'):
        shutil.copy2(source/name,destination/name)
    (destination/'impl').mkdir(exist_ok=True)
    shutil.copy2(source/'impl/tanglab_process_config.json',destination/'impl/tanglab_process_config.json')
    bit=destination/'tanglab-piano-v1.3.1.fs'
    if bit.exists():bit.chmod(0o666)
    shutil.copy2(source/'impl/pnr/tanglab.fs',bit)
    for stage in ('gwsynthesis','pnr'):
        target=destination/'reports'/stage;target.mkdir(parents=True,exist_ok=True)
        for p in (source/'impl'/stage).iterdir():
            if p.suffix in ('.html','.txt') and p.is_file():shutil.copy2(p,target/p.name)
    for p in (root/'docs').glob('*1.3*'):
        if p.is_file():shutil.copy2(p,destination/p.name)
    shutil.copy2(root/'钢琴音色使用说明.txt',destination/'钢琴音色使用说明.txt')
    (destination/'工程与烧录入口.txt').write_text(
        '当前版本：TangLab 1.3.1（2026-10-08）\n'
        '直接烧录：本目录tanglab-piano-v1.3.1.fs，用官方Programmer选择SRAM下载。\n'
        '打开工程：本目录tanglab.gprj；器件GW5AST-LV138PG484AC1/I0。\n'
        '整个文件夹一起复制；impl/tanglab_process_config.json是必要IDE配置，不能删除。\n'
        'CPU/SSPI已作GPIO，以免J9出现dedicated pin约束错误。\n'
        '命令行重编译：在本目录用Gowin IDE/bin/gw_sh.exe运行build.tcl。\n'
        '重编译结果：impl/pnr/tanglab.fs；根目录交付fs不会自动覆盖。\n'
        '50MHz时钟、上电静音、921600串口、3.3V IMU接口；接线与前版相同。\n'
        '新固件未自动烧录。完整步骤见钢琴音色使用说明.txt及上板测试指南。\n',encoding='utf-8')
    paths=[bit,destination/'tanglab.gprj',destination/'tanglab.cst',destination/'tanglab.sdc',
           destination/'impl/tanglab_process_config.json',*sorted((destination/'rtl').glob('*.v'))]
    (destination/'SHA256.txt').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(destination).as_posix() for p in paths)+'\n',encoding='utf-8')
    return destination

if __name__=='__main__':print(package(Path(__file__).resolve().parent,sys.argv[1]))
