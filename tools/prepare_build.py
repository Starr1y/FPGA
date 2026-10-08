"""Flatten the repository into a NEW build folder expected by build_exe.py."""
from pathlib import Path
import argparse,shutil
p=argparse.ArgumentParser(description='生成独立构建目录，不修改当前仓库或记录')
p.add_argument('destination',help='新的空目录，建议D盘');a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(a.destination).resolve()
if out.exists():raise SystemExit('目标已存在，请选新的目录')
if out.is_relative_to(root):raise SystemExit('构建目录应位于仓库之外')
out.mkdir(parents=True)
for f in (root/'source').glob('*.py'):shutil.copy2(f,out/f.name)
shutil.copytree(root/'source/tests',out/'tests')
for name in ('fpga','docs','board-test'):shutil.copytree(root/name,out/name)
for f in root.iterdir():
 if f.is_file() and f.suffix in ('.txt','.md'):shutil.copy2(f,out/f.name)
shutil.copy2(root/'requirements-lock.txt',out/'requirements-lock.txt')
print('构建目录：'+str(out));print('在该目录运行：python build_exe.py --package-only')
