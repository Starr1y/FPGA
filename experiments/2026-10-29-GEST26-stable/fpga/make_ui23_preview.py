"""Publish real RTL raster examples after run_ui23_tests.sh; not a UI mockup."""
from pathlib import Path
import json,hashlib,datetime,html
from PIL import Image
R=Path(__file__).resolve().parent;V=R/'validation';P=R/'preview'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
tests=['tb_ui23_events','tb_ui21_controls','tb_ui21_encoder','tb_ui21_lesson','tb_ui21_stop','tb_ui23_panel']
assert all('TB_PASS' in (V/(n+'.log')).read_text(encoding='utf-8',errors='replace') for n in tests),'Test not finished or failed'
snapshot=json.loads((V/'source_before_build.json').read_text(encoding='utf-8'))
assert all(sha(R/n)==h for n,h in snapshot['sha256'].items()),'Build/test sources changed'
address_proof=json.loads((V/'ui23_address.json').read_text(encoding='utf-8'))
assert address_proof['status']=='PASS' and address_proof['checks']==16384
assert address_proof['rtl_sha256']==sha(R/'rtl/duo04_panel.v')
log=(V/'tb_ui23_panel.log').read_text(encoding='utf-8')
assert all(f'SCENE_PASS {i} ' in log for i in range(14))
names=['双手演奏','快捷菜单','教学目标','单手离线诊断','参数编辑','十二音区','五音区','教学正确','教学错击','复位二次确认','全局停止与右手离线','教学完成','真实击发反馈','电脑输入与物理IMU状态分离']
frames={}
for i in range(14):
    ppm=P/f'ui23-{i}.ppm';im=Image.open(ppm);assert im.size==(640,480)
    im.save(P/f'ui23-{i}.png');frames[ppm.name]=sha(ppm)
before=V/'synthesis-attempt01/reference_raster_hashes.json'
equivalent=None
if before.exists():
    old=json.loads(before.read_text(encoding='utf-8'))
    equivalent=all(frames[n]==h for n,h in old.items() if n!='ui23-3.ppm')
    assert equivalent,'ROM/width refactor changed pixels outside the intentional offline diagnostic change'
contact=Image.new('RGB',(1280,960),'white')
for i,(xx,yy) in enumerate([(0,0),(640,0),(0,480),(640,480)]):contact.paste(Image.open(P/f'ui23-{i}.png'),(xx,yy))
contact.save(P/'ui23-four-pages.png')
cards=''.join(f'<figure><img src="ui23-{i}.png" width="640" height="480" alt="{html.escape(n)}"><figcaption>{i+1:02d} {html.escape(n)} · RTL 仿真示例数据</figcaption></figure>' for i,n in enumerate(names))
(P/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>TangLab UI23 页面验证</title><style>body{background:#f3dfb5;color:#242532;font:16px system-ui;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax( min(100%,640px),1fr));gap:24px}figure{margin:0}img{width:100%;height:auto;image-rendering:pixelated;border-radius:8px}figcaption{padding:8px}p{max-width:76em;line-height:1.8}</style><h1>TangLab UI23 · 实际 RTL 像素输出</h1><p>下列图片来自 Icarus 运行硬件页面逻辑后的完整 640×480 栅格，不是浏览器复刻。数值与连接状态来自测试输入，仅为示例；不代表实板状态、综合时序或传感器测量。照片示意图中的 KEY0 开始/暂停未沿用，真实程序中 KEY0 仍为归中。</p><main>'''+cards+'</main></html>',encoding='utf-8')
current=json.loads((R/'ui23-assets.json').read_text(encoding='utf-8'))
oldmeta=json.loads((R.parent/'duo04_io22/panel-font.json').read_text(encoding='utf-8'))
new_bits=sum(current[k] for k in ('font_used_bits','text_used_bits','hand_bits','logo_bits','fan_bits'))
old_bits=oldmeta['glyph_rows']*20+oldmeta['text_words']*9+98280
proof={'status':'PASS','completed':datetime.datetime.now().astimezone().isoformat(),'test_logs':{n:sha(V/(n+'.log')) for n in tests},'address_proof_sha256':sha(V/'ui23_address.json'),'full_raster_scenes':14,'pixels_per_scene':307200,'source_snapshot_sha256':sha(V/'source_before_build.json'),'equivalent_after_width_fix':equivalent,'intentional_changed_scene':'ui23-3: disconnected IMU shows unknown centering instead of a derived result','additional_scene':'ui23-13: computer input does not require or impersonate physical IMU links','raster_sha256':frames,'rom_payload_bits':{'ui23':new_bits,'io22':old_bits,'scope':'useful monochrome data, not inferred/routed block count or measured power'},'hardware_test':'NOT RUN','implementation_test':'See current build_status.json; not implied by UI tests'}
(V/'ui23_tests.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'status':'PASS','test_count':len(tests),'raster_scenes':14,'equivalent_pixels':equivalent,'ROM_payload_bits':[old_bits,new_bits]},ensure_ascii=False))
