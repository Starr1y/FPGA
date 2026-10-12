"""One-time standalone parameter-menu font assembly; no board access."""
from pathlib import Path
import json,hashlib,sys
from PIL import Image,ImageFont,ImageDraw
R=Path(__file__).resolve().parents[2];W=R/'fpga/controls_display';D=W/'rtl'
LABELS={
 'TITLE':'乐器设置','HAND_L':'左手','HAND_R':'右手','SELECT':'选择','EDIT':'编辑',
 'PAGE_FOCUS':'操作手','PAGE_TIMBRE':'音色','PAGE_RELEASE':'尾音','PAGE_EFFECT':'音效','PAGE_WET':'湿声',
 'PAGE_DELAY':'延迟','PAGE_FEEDBACK':'反馈','PAGE_DEPTH':'合唱深度','PAGE_MODE':'演奏模式','PAGE_MUTE':'静音','PAGE_LAYOUT':'音区布局',
 'PLUCK':'拨弦','BASS':'贝斯','WIND':'管乐','BELL':'铃音','BYPASS':'旁路','CHORUS':'合唱','REVERB':'混响',
 'MELODIES':'双旋律','CHORD':'左手和弦','OFF':'关闭','ON':'开启','MS':'毫秒','SECOND':'秒','SAMPLES':'采样',
 'ROTATE':'旋转选择','CLICK':'短按编辑','BACK':'长按返回','HAND_SETTINGS':'当前手参数','GLOBAL_SETTINGS':'全局参数',
 'SEVEN':'七音','FIVE':'五音','TWELVE':'十二半音','FIXED_ZERO':'固定零','UNKNOWN':'未知',
 'ROTATE_EDIT':'旋转调整','CLICK_EDIT':'短按完成'}
def main():
 assert not (D/'menu_font.hex').exists() or '--regenerate-fonts' in sys.argv,'Use --regenerate-fonts only for an intentional font/label update'
 D.mkdir(parents=True,exist_ok=True);(W/'tb').mkdir(exist_ok=True)
 source=json.loads((R/'docs/reference/fonts/wenkai-source.json').read_text(encoding='utf8'))
 path=R/'docs/reference/fonts/LXGWWenKaiMono-Medium.ttf'
 assert hashlib.sha256(path.read_bytes()).hexdigest()==source['font_sha256']
 font=ImageFont.truetype(str(path),20);chars=[' ']+sorted(set(''.join(LABELS.values())));assert len(chars)<=128
 words=[]
 for char in chars:
  image=Image.new('L',(24,24));ImageDraw.Draw(image).text((2,-1),char,font=font,fill=255)
  for y in range(24):words.append(f'{sum(1<<(23-x) for x in range(24) if image.getpixel((x,y))>=160):06x}')
 (D/'menu_font.hex').write_text('\n'.join(words)+'\n',encoding='utf8')
 (D/'menu_font.v').write_text(f'''// TangLab Menu Bitmap; WenKai Mono 20px / 24x24; SIL OFL 1.1.
module menu_font(input clk,enabled,input[6:0]glyph,input[4:0]row,output reg[23:0]bits);
reg[23:0]rom[0:{len(words)-1}] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/menu_font.hex",rom);
wire[11:0]g={{5'b0,glyph}};
wire[11:0]address=(g<<4)+(g<<3)+(row<24 ? row : 0);
always @(posedge clk)if(enabled)bits<=rom[address];
endmodule
''',encoding='utf8')
 s='module menu_labels(input[5:0]label_id,input[4:0]position,output reg[6:0]glyph);\nalways @*begin glyph=0;case(label_id)\n'
 constants='// Generated label numbers; regenerate with the matching font ROM only.\n'
 for i,(name,label) in enumerate(LABELS.items()):
  constants+=f'localparam [5:0] L_{name}=6\'d{i};\n'
  s+=f'{i}:case(position)\n'+''.join(f'{j}:glyph={chars.index(ch)};\n' for j,ch in enumerate(label))+'default:glyph=0;endcase\n'
 (D/'menu_labels.v').write_text(s+'default:glyph=0;endcase end\nendmodule\n',encoding='utf8')
 (D/'menu_labels.vh').write_text(constants,encoding='utf8')
 ascii_chars=[' ']+list('0123456789.%'+'-');ascii_words=[]
 for char in ascii_chars:
  image=Image.new('L',(13,24));ImageDraw.Draw(image).text((2,-1),char,font=font,fill=255)
  for y in range(24):ascii_words.append(f'{sum(1<<(12-x) for x in range(13) if image.getpixel((x,y))>=160):04x}')
 (D/'menu_ascii.hex').write_text('\n'.join(ascii_words)+'\n',encoding='utf8')
 s='module menu_ascii(input clk,enabled,input[7:0]ch,input[4:0]row,output reg[12:0]bits);\nreg[3:0]glyph;\nalways @*begin glyph=0;case(ch)\n'
 for i,char in enumerate(ascii_chars):s+=f"8'd{ord(char)}:glyph=4'd{i};\n"
 s+='default:glyph=0;endcase end\n'
 s+=f'''reg[12:0]rom[0:{len(ascii_words)-1}] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/menu_ascii.hex",rom);
wire[8:0]g={{5'b0,glyph}};
wire[8:0]address=(g<<4)+(g<<3)+(row<24 ? row : 0);
always @(posedge clk)if(enabled)bits<=rom[address];
endmodule
'''
 (D/'menu_ascii.v').write_text(s,encoding='utf8')
 (W/'font-labels.json').write_text(json.dumps({'font_sha256':source['font_sha256'],'pixel_size':20,'cell':[24,24],'ascii_cell':[13,24],'threshold':160,'labels':LABELS,'glyphs':chars,'ascii_glyphs':ascii_chars},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print('Menu display glyphs:',len(chars))
if __name__=='__main__':main()
