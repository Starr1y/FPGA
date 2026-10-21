"""Freeze only after independent current-source implementation/UI checks pass."""
from pathlib import Path
import json,hashlib,shutil,subprocess,sys,datetime
from summarize_ui23_synthesis import summarize
R=Path(__file__).resolve().parent;V=R/'validation';N='tanglab_duo04_ui23'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def freeze():
 subprocess.run([sys.executable,'-X','utf8',str(R/'check_imu_pads.py')],cwd=R,check=True)
 check=subprocess.run([sys.executable,'-X','utf8',str(R/'check_implementation.py')],cwd=R,capture_output=True,text=True,encoding='utf-8',check=True)
 implementation=json.loads(check.stdout)
 assert implementation['status']=='IMPLEMENTED, BOARD VALIDATION PENDING'
 (V/'implementation_check.json').write_text(check.stdout,encoding='utf-8')
 snapshot=json.loads((V/'source_before_build.json').read_text(encoding='utf-8'))
 ui=json.loads((V/'ui23_tests.json').read_text(encoding='utf-8'))
 assert ui['status']=='PASS' and ui['full_raster_scenes']==14 and ui['source_snapshot_sha256']==sha(V/'source_before_build.json')
 assert all(sha(V/(n+'.log'))==h for n,h in ui['test_logs'].items())
 addr=json.loads((V/'ui23_address.json').read_text(encoding='utf-8'))
 assert addr['status']=='PASS' and addr['checks']==16384 and addr['rtl_sha256']==sha(R/'rtl/duo04_panel.v')
 synthesis=summarize()
 assert all(sha(R/n)==h for n,h in snapshot['sha256'].items())
 dst=R/'bitstream';dst.mkdir(exist_ok=True);bit=R/'impl/pnr'/(N+'.fs');shutil.copy2(bit,dst/bit.name)
 out=R/'reports/pnr';out.mkdir(parents=True,exist_ok=True)
 for p in bit.parent.iterdir():
  if p.suffix in ('.html','.log','.do','.txt'):shutil.copy2(p,out/p.name)
 report_hashes={p.relative_to(R).as_posix():sha(p) for d in (R/'reports/pnr',R/'reports/synthesis') for p in d.iterdir() if p.is_file()}
 manifest={'schema':'tanglab-ui23-release-1','project':'TangLab UI23','base_commit':'554124f',
  'frozen_at':datetime.datetime.now().astimezone().isoformat(),'hardware_test':'NOT RUN',
  'bitstream':{'file':'bitstream/'+bit.name,'sha256':sha(bit),'bytes':bit.stat().st_size},
  'source_snapshot_sha256':sha(V/'source_before_build.json'),'sources':snapshot['sha256'],
  'supplemental_inherited_root_rom_sha256':synthesis['supplemental_inherited_root_rom_sha256'],
  'implementation_check_sha256':sha(V/'implementation_check.json'),'synthesis_provenance_sha256':sha(V/'synthesis_provenance.json'),
  'ui_tests_sha256':sha(V/'ui23_tests.json'),'address_tests_sha256':sha(V/'ui23_address.json'),
  'required_clocks_mhz':{'core':50,'pixel':25},'reports':report_hashes}
 (R/'FIRMWARE.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
 hashes={**manifest['sources'],**manifest['supplemental_inherited_root_rom_sha256'],**report_hashes,manifest['bitstream']['file']:manifest['bitstream']['sha256']}
 (R/'SHA256.txt').write_text(''.join(f'{h}  {n}\n' for n,h in sorted(hashes.items())),encoding='ascii')
 text=(R/'README.md').read_text(encoding='utf-8')
 a=text.index('<!-- UI23_RELEASE_STATUS_START -->');b=text.index('<!-- UI23_RELEASE_STATUS_END -->')+len('<!-- UI23_RELEASE_STATUS_END -->')
 text=text[:a]+'''<!-- UI23_RELEASE_STATUS_START -->
**本版本已通过当前源码的完整综合、布局布线 setup/hold 与 50 MHz / 25 MHz 检查，以及页面/交互和地址等价验证。实板与实际音频/动作延迟仍待测试。**

[下载 UI23 位流](bitstream/tanglab_duo04_ui23.fs) · [冻结清单](FIRMWARE.json) · [实际 RTL 页面预览](preview/index.html)
<!-- UI23_RELEASE_STATUS_END -->'''+text[b:]
 (R/'README.md').write_text(text,encoding='utf-8')
 board=R/'BOARD_VALIDATION.md';t=board.read_text(encoding='utf-8').replace('当前源码提交不包含已验收 UI23 位流。','本目录现已包含通过当前源码时序检查的 UI23 位流；下载前仍须核对冻结清单与哈希。')
 board.write_text(t,encoding='utf-8')
 print(json.dumps({'status':'FROZEN','bitstream_sha256':sha(bit)}))
 return manifest
if __name__=='__main__':freeze()
