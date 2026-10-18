"""Build small Chinese glyph/text ROMs. Usage: python generate_panel.py FONT.ttf.
Font: Noto Serif CJK SC, SIL OFL 1.1. Rendered glyphs only; no framebuffer.
"""
from pathlib import Path
import sys,json,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parent
fields=['演奏模式','左手音色','右手音色','左手音阶','右手音阶','左手八度','右手八度','左手和弦','总音量','音效类型','音效湿度','左手保持毫秒','右手保持毫秒','左手释音档位','右手释音档位','左手颤音','右手颤音','左手滑音','右手滑音','教学曲目']
pages=[['TANGLAB  双手演奏', '', '操作手             状态', '', '', '', '左手                 右手', '', '', '', '', '', '', '', '', '', '', '选区                 选区', '', '力度                 力度', '', '旋钮调音量 按下打开快捷菜单', 'K0归中 K1音色 K2切换手', 'K0加K2停止 K0加K1设置'], ['TANGLAB  快捷与设置', '', '旋转选择  短按进入或确认', '长按返回  K0确认 K1加 K2减', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '当前值', 'K0加K2全局停止', '数值实时生效  复位须再确认'], ['TANGLAB  逐音等待教学', '', '目标手             进度', '', '', '', '左手                 右手', '', '', '', '', '', '', '', '', '', '', '正确                 错击', '', '', '', '金色目标 绿闪正确 红色错击', '旋钮调音量 按下开始或暂停', 'K0加K2停止 K0加K1设置'], ['TANGLAB  诊断与归中', '', '左手在线            右手在线', '', '', '', '归中结果', '', '', '', '', '', '按K0归中当前操作手', '', 'K1加K2返回演奏或教学', '', '状态来自实际板内读回', '', '2.1交互版需重新编译下载', '', 'PR1014仍需检查布线报告']]
extra=['演奏模式', '左手音色', '右手音色', '左手音阶', '右手音阶', '左手八度', '右手八度', '左手和弦', '总音量', '音效类型', '音效湿度', '左手保持毫秒', '右手保持毫秒', '左手释音档位', '右手释音档位', '左手颤音', '右手颤音', '左手滑音', '右手滑音', '教学曲目', '钢琴', '马林巴', '电钢琴', '拨弦', '脱机', '电脑', '教学', '等待', '演奏', '停止', '左手', '右手', '在线', '离线', '完成', '选择', '编辑', '教学输入来源', '重新归中双手', '确认复位当前手', '开始或暂停', '演奏或教学', '当前手设置', '完整设置', '诊断状态', '左手设置', '右手设置', '音效设置', '表情设置', '教学设置', '系统设置', '旋转选择分组', '旋转选择参数', '再次确认才执行', '鼠标教学测试', 'IMU脱机教学', '等待归中', '归中完成', '归中失败', '教学中禁止换区', '短按确认编辑', 'DO RE MI FA SOL LA SI']
note_labels=['DO','RE','MI','FA','SOL','LA','SI','DO','RE','MI','SOL','LA','DO','DO#','RE','RE#','MI','FA','FA#','SOL','SOL#','LA','LA#','SI']
extra+=note_labels
extra+=['七音区','五音区','十二音区','C4 原调','C5 高八度','C2 低两组','C3 低一组','关闭','开启','释音0.2秒','释音0.5秒','释音1.5秒','左手七音练习','右手七音练习','双手交替练习','选择中','编辑中 已生效','确认复位','当前音量','复位会中断当前手']
extra+=['重新开始练习']
extra+=['%']
chars=[' ']+sorted(set(''.join(sum(pages,[])+extra)+'0123456789:- /')-{' '})
assert len(chars)<512
fontfile=Path(sys.argv[1]);font=ImageFont.truetype(str(fontfile),18)
try:font.set_variation_by_axes([600])
except (OSError,ValueError):pass
words=[]
for ch in chars:
    im=Image.new('L',(20,20));d=ImageDraw.Draw(im);bbox=d.textbbox((0,0),ch,font=font)
    d.text(((20-(bbox[2]-bbox[0]))//2-bbox[0],-bbox[1]),ch,font=font,fill=255)
    for y in range(20):words.append(f'{sum(1<<(19-x) for x in range(20) if im.getpixel((x,y))>=128):05x}')
(ROOT/'rtl/duo04_font.hex').write_text('\n'.join(words)+'\n')
rom=[]
for page in pages:
    for row in range(24):
        line=page[row] if row<len(page) else ''
        assert len(line)<=32,line
        rom.extend(chars.index(c) for c in line.ljust(32))
for label in extra:rom.extend(chars.index(c) for c in label.ljust(32))
(ROOT/'rtl/duo04_text.hex').write_text(''.join(f'{c:03x}\n' for c in rom))
(ROOT/'panel-font.json').write_text(json.dumps(dict(chars=chars,pages=pages,fields=fields,labels=extra,font='Noto Serif SC',font_sha256=hashlib.sha256(fontfile.read_bytes()).hexdigest(),glyph_rows=len(words),text_words=len(rom)),ensure_ascii=False,indent=2),encoding='utf-8')
print('glyphs',len(chars),'glyph rows',len(words),'text words',len(rom))

(ROOT/'rtl/duo04_digits.vh').write_text('function[8:0]digit_glyph;input[3:0]d;begin case(d)\n'+''.join(f'{i}:digit_glyph={chars.index(str(i))};\n' for i in range(10))+'default:digit_glyph=0;endcase end endfunction\n')
