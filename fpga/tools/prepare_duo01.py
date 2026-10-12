"""Assemble standalone DUO01 dependencies and compact ROM assets. No board access."""
from pathlib import Path
import hashlib,json,math,shutil
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo01';D=W/'rtl'
PROFILES=[['DO','RE','MI','FA','SOL','LA','SI'],['DO','RE','MI','SOL','LA'],['DO','DO#','RE','RE#','MI','FA','FA#','SOL','SOL#','LA','LA#','SI']]
LABELS=['姿态乐器','左手','右手','静音','发声','演奏','诊断','待使能','离线','归中中','等待归中','越界','低精度','可击发','表情',
        '七音','五音','十二音','拨弦','贝斯','管乐','铃音','预选','上次','力度','击发','偏航','俯仰','横滚','精度','双旋律','左手和弦',
        '换手','归中','换区','音色','复位','启停','声音','模式','长按','按键','错误停机']
def write(name,s): (D/name).write_text(s,encoding='utf8')
def main():
 # This bootstrap generator must not overwrite reviewed timing fixes.
 assert not (W/'tanglab_duo01.gprj').exists(), 'DUO01 already assembled; edit existing RTL instead of reinitializing it'
 D.mkdir(parents=True,exist_ok=True); (W/'tb').mkdir(exist_ok=True)
 sources={}
 sets=[(R/'fpga/i2cfan04/rtl',['bno_i2c_host.v','shtp_i2c_link.v','i2c_byte_master.v','shtp_report_decode.v','quaternion_pose.v','pose_math.v','gesture_control.v','expression_stream_guard.v','hand_expression.v','video_font.v','pt8211_output.v','video_status_cdc.v','video_pll_125.v','svo_tmds.v']),
       (R/'fpga/dualhand/rtl',[p.name for p in (R/'fpga/dualhand/rtl').glob('*.v')]),
       (R/'fpga/dualhand/synthdeps/rtl',[p.name for p in (R/'fpga/dualhand/synthdeps/rtl').iterdir() if p.suffix in ('.v','.hex')])]
 for base,names in sets:
  for name in names:
   shutil.copyfile(base/name,D/name);sources[(base/name).relative_to(R).as_posix()]=hashlib.sha256((base/name).read_bytes()).hexdigest()
 # Chinese glyphs are monochrome WenKai at native size, no dilation/upscaling.
 font=ImageFont.truetype(str(R/'docs/reference/fonts/LXGWWenKaiMono-Medium.ttf'),20)
 chars=[' ']+sorted(set(''.join(LABELS))); words=[]
 for ch in chars:
  im=Image.new('L',(24,24));ImageDraw.Draw(im).text((2,-1),ch,font=font,fill=255)
  for y in range(24):words.append(f'{sum(1<<(23-x) for x in range(24) if im.getpixel((x,y))>=160):06x}')
 write('duo_font.hex','\n'.join(words)+'\n')
 write('duo_font.v',f'''// WenKai Mono derivative; SIL OFL 1.1. See docs/reference/fonts/WenKai-OFL.txt.
module duo_font(input clk,input [6:0]glyph,input [4:0]row,output reg[23:0]bits);
reg[23:0]rom[0:{len(words)-1}] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/duo_font.hex",rom);
always @(posedge clk)bits<=rom[glyph*24+(row<24 ? row : 0)];
endmodule
''')
 s='module duo_text(input[5:0]label_id,input[4:0]position,output reg[6:0]glyph);\nalways @* begin glyph=0;case(label_id)\n'
 for i,label in enumerate(LABELS):
  s+=f'{i}:case(position)\n'+''.join(f'{j}:glyph={chars.index(ch)};\n' for j,ch in enumerate(label))+'default:glyph=0;endcase\n'
 write('duo_text.v',s+'default:glyph=0;endcase end\nendmodule\n')
 words=[]
 for notes in PROFILES:
  for row in range(140):
   groups=[[] for _ in range(12)];hole=[]
   for col in range(280):
    dx=col-140;dy=row-139;r2=dx*dx+dy*dy
    if r2<=136**2:
     z=min(len(notes)-1,max(0,int((math.degrees(math.atan2(dx,-dy))+90)*len(notes)/180)))
     groups[z].append(col)
    if r2<36**2:hole.append(col)
   word=0
   for i,xs in enumerate(groups+[hole]):
    lo,hi=(min(xs),max(xs)) if xs else (511,0);word|=(lo|(hi<<9))<<(18*i)
   words.append(f'{word:059x}')
 write('duo_spans.hex','\n'.join(words)+'\n')
 write('duo_fan.v','''module duo_fan(input clk,rst_n,input[1:0]profile,input[8:0]col,row,input enabled,
 output reg[11:0]zones,output reg boundary);
reg[233:0]rom[0:419] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/duo_spans.hex",rom);
wire valid=enabled && col<280 && row<140;
wire[8:0]address=(profile==1 ? 9'd140 : profile==2 ? 9'd280 : 9'd0)+row;
reg[233:0]line;reg[8:0]col_p;reg valid_p;integer i;reg hole;
always @(posedge clk)begin line<=rom[valid ? address : 0];col_p<=col;valid_p<=rst_n && valid;end
always @* begin zones=0;boundary=0;hole=col_p>=line[216+:9] && col_p<=line[225+:9];
if(valid_p && !hole)for(i=0;i<12;i=i+1)if(col_p>=line[i*18+:9] && col_p<=line[i*18+9+:9])begin
zones[i]=1;if(col_p<=line[i*18+:9]+1 || col_p+1>=line[i*18+9+:9])boundary=1;end
end
endmodule
''')
 (W/'dependency-sources.json').write_text(json.dumps(sources,indent=2)+'\n')
 # Generated note widget snippets are expanded into the panel's selector.
 note_widgets=''
 for p,notes in enumerate(PROFILES):
  note_widgets+=f'if(profile=={p})begin\n'
  for i,note in enumerate(notes):
   angle=math.radians(-90+(i+.5)*180/len(notes));xx=round(140+112*math.sin(angle)-len(note)*4); yy=round(139-112*math.cos(angle)-6)+200
   note_widgets+=f'if(col>={xx} && col<{xx+len(note)*8} && y>={yy} && y<{yy+12})begin text="{note}";text_len={len(note)};tx=base+{xx};ty={yy};end\n'
  note_widgets+='end\n'
 (W/'note-widgets.txt').write_text(note_widgets)
 print('Prepared dependency snapshots,',len(chars),'Chinese glyphs, 3 fan profiles')
if __name__=='__main__':main()
