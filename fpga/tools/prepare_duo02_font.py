"""Build DUO02 WenKai labels only; never regenerates panel or frozen sources."""
from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont
from prepare_duo01 import LABELS
R=Path(__file__).resolve().parents[2];D=R/'fpga/duo02/rtl'
labels=LABELS+['旁路','延迟','合唱','混响','音效','等待数据','回位等待','重新归中','湿声']
font_path=R/'docs/reference/fonts/LXGWWenKaiMono-Medium.ttf'
source=json.loads((R/'docs/reference/fonts/wenkai-source.json').read_text(encoding='utf8'))
assert hashlib.sha256(font_path.read_bytes()).hexdigest()==source['font_sha256'],'Unexpected WenKai font file/version'
font=ImageFont.truetype(str(font_path),20);chars=[' ']+sorted(set(''.join(labels)))
assert len(chars)<=128
words=[]
for ch in chars:
 im=Image.new('L',(24,24));ImageDraw.Draw(im).text((2,-1),ch,font=font,fill=255)
 for y in range(24):words.append(f'{sum(1<<(23-x) for x in range(24) if im.getpixel((x,y))>=160):06x}')
(D/'duo_font.hex').write_text('\n'.join(words)+'\n',encoding='utf8')
(D/'duo_font.v').write_text(f'''// TangLab Duo Bitmap, WenKai Mono 20px / 24x24; SIL OFL 1.1.
module duo_font(input clk,input [6:0]glyph,input [4:0]row,output reg[23:0]bits);
reg[23:0]rom[0:{len(words)-1}] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/duo_font.hex",rom);
always @(posedge clk)bits<=rom[glyph*24+(row<24 ? row : 0)];
endmodule
''',encoding='utf8')
s='module duo_text(input[5:0]label_id,input[4:0]position,output reg[6:0]glyph);\nalways @* begin glyph=0;case(label_id)\n'
for i,label in enumerate(labels):
 s+=f'{i}:case(position)\n'+''.join(f'{j}:glyph={chars.index(ch)};\n' for j,ch in enumerate(label))+'default:glyph=0;endcase\n'
(D/'duo_text.v').write_text(s+'default:glyph=0;endcase end\nendmodule\n',encoding='utf8')
(D.parent/'font-labels.json').write_text(json.dumps({'labels':labels,'glyphs':chars,'font_sha256':hashlib.sha256(font_path.read_bytes()).hexdigest(),'pixel_size':20,'cell':[24,24],'threshold':160},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('DUO02 glyphs',len(chars))
