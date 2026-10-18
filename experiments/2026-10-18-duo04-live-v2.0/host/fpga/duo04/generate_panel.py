"""Build small Chinese glyph/text ROMs. Usage: python generate_panel.py FONT.ttf.
Font: Noto Serif CJK SC, SIL OFL 1.1. Rendered glyphs only; no framebuffer.
"""
from pathlib import Path
import sys,json,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parent
fields=['演奏模式','左手音色','右手音色','左手音阶','右手音阶','左手八度','右手八度','左手和弦','总音量','音效类型','音效湿度','左手保持毫秒','右手保持毫秒','左手释音档位','右手释音档位','左手颤音','右手颤音','左手滑音','右手滑音','教学曲目']
pages=[[
'TANGLAB  双手演奏实验室','', '演奏     设置     教学     状态','',
'模式            状态', '', '左手                 右手', '', '音色                 音色', '',
'', '', '', '', '', '', '',
'左手选区             右手选区','', '力度                 力度','',
'旋转切页  短按开始或停止','32声部实时合成   48 kHz','长按返回  KEY2紧急静音'
],[
'TANGLAB  演奏设置','', '旋转选项   短按进入或确认','长按退出并返回演奏页','',
'当前选项','', '当前值','', '音色 0钢琴 1马林巴','     2电钢琴 3拨弦', '',
'模式 0脱机 1电脑 2教学','八度 0原调 1高八度 2低两组 3低一组','释音 0短 1中 2长', '',
'保持时间到点松键，随后自然释音','自然衰减可早于松键变轻'],[
'TANGLAB  逐音教学','', '先归中双手，按目标音区击发','弹对前进，错击保留当前目标','',
'练习曲目','', '进度','', '目标手      目标音区      音符','',
'正确数量          错击数量','', '短按开始或重新练习', '旋转切页，长按返回','',
'曲目 0左手 1右手 2双手交替','曲目存储音符事件，不播放录音'],[
'TANGLAB  校准与状态','', '左手传感器       右手传感器','',
'短按为双手重新归中','归中时保持双手静止', '',
'EC11仅接3.3V逻辑','A/B旋转  SW按键  共地', '',
'上电默认静音','KEY2为全局紧急静音', '',
'脱机演奏不依赖电脑心跳','教学LED接口预留，尚未接入', '',
'参数仅本次上电有效']]
extra=fields+['钢琴','马林巴','电钢琴','拨弦','脱机','电脑','教学','等待','演奏','停止','左手','右手','在线','离线','完成','选择','编辑']
chars=[' ']+sorted(set(''.join(sum(pages,[])+extra)+'0123456789:- /')-{' '})
assert len(chars)<256
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
for label in fields+extra[len(fields):]:rom.extend(chars.index(c) for c in label.ljust(32))
(ROOT/'rtl/duo04_text.hex').write_text(''.join(f'{c:02x}\n' for c in rom))
(ROOT/'panel-font.json').write_text(json.dumps(dict(chars=chars,pages=pages,fields=fields,labels=extra[len(fields):],font='Noto Serif SC',font_sha256=hashlib.sha256(fontfile.read_bytes()).hexdigest(),glyph_rows=len(words),text_words=len(rom)),ensure_ascii=False,indent=2),encoding='utf-8')
print('glyphs',len(chars),'glyph rows',len(words),'text words',len(rom))

(ROOT/'rtl/duo04_digits.vh').write_text('function[7:0]digit_glyph;input[3:0]d;begin case(d)\n'+''.join(f'{i}:digit_glyph={chars.index(str(i))};\n' for i in range(10))+'default:digit_glyph=0;endcase end endfunction\n')
