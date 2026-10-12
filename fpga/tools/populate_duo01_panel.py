"""Expand the DUO01 pixel widgets once, retaining generated RTL for reproduction."""
from pathlib import Path
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo01';P=W/'rtl/duo_panel.v'
def widget(x,y,n,text=None,label=None,large=False,ink=1):
 zh=label is not None;width=26 if zh else 16 if large else 8;height=24 if zh or large else 12
 return f'if(x>={x} && x<({x})+{n}*{width} && y>={y} && y<{y+height})begin zh={int(zh)};doubled={int(large)};tx={x};ty={y};text_len={n};ink={ink};'+(f'label_id={label};' if zh else f'text={text};')+'end\n'
def main():
 s=P.read_text();assert '// WIDGETS' in s,'Widgets already expanded'
 w=widget('32',28,7,'"TANGLAB"',large=True)+widget('176',28,4,label=0)
 w+=widget('372',28,4,label='ui[525] ? 31 : 30')+widget('548',28,2,label='ui[524] ? 3 : 4',ink=2)
 w+=widget('32',68,5,'"DUO01"')+widget('192',60,2,label='diag ? 6 : 5')
 w+=widget('328',68,17,'"I2C / 32 VOICE   "')+widget('552',68,4,'ui[522] ? "KEY2" : "KEY1"') # replaced below with hand focus label
 w=w.replace('text=ui[522] ? "KEY2" : "KEY1";','text=ui[522] ? "R   " : "L   ";')
 w+=widget('base+8',112,2,label='hand ? 2 : 1')+widget('base+120',112,5,label='state_label',ink='state_label==13 ? 1 : 2')
 w+=widget('base+8',156,3,label='profile==1 ? 16 : profile==2 ? 17 : 15')
 w+=widget('base+174',156,2,label='18+preset')
 w+='if(!diag)begin\n'+(W/'note-widgets.txt').read_text()+'\n'
 w+=widget('base+8',356,2,label=22)
 w+=widget('base+64',356,4,'s[4] ? note(profile,s[21:18]) : "----"',large=True)
 w+=widget('base+136',356,2,label=23,ink=2)
 w+=widget('base+192',356,4,'s[159:128]!=0 ? note(s[27:26],s[25:22]) : "----"',large=True,ink=2)
 w+='end else begin\n'
 for a,lab in enumerate((26,27,28)):
  y=200+a*38;w+=widget('base+8',y,2,label=lab)
  val='{(s['+str(47+a*16)+'] ? "-" : "+"),digit((hand ? 4 : 0)+'+str(a)+',1),digit((hand ? 4 : 0)+'+str(a)+',2),digit((hand ? 4 : 0)+'+str(a)+',3)}'
  w+=widget('base+100',y,4,val,large=True)
 w+=widget('base+8',316,20,'{"RX ",hex4(s[191:176])," PKT ",hex4(s[175:160]),"    "}')
 w+=widget('base+8',336,12,'{"ERR ",hex8(s[223:192])}',ink=2)
 w+=widget('base+160',336,8,'{"RST ",hex4(s[239:224])}',ink=2)
 w+=widget('base+8',356,23,'{"HZ P",hex4(ui[640+hand*48+:16])," A",hex4(ui[656+hand*48+:16])," G",hex4(ui[672+hand*48+:16]),"   "}')
 w+=widget('base+8',376,8,'{"QUAL ",("0"+{6\'b0,s[9:8]}),"/3"}')
 w+=widget('base+160',376,9,'{"HIT ",digit(hand ? 7 : 3,0),digit(hand ? 7 : 3,1),digit(hand ? 7 : 3,2),digit(hand ? 7 : 3,3)," "}')
 w+='end\n'
 for xx,yy,key,lab1,lab2 in [('32',414,'KEY0',33,34),('328',414,'KEY2',32,36),('32',444,'KEY1',35,14),('328',444,'KEY1+2',6,37)]:
  w+=widget(xx,yy+6,len(key),f'"{key}"')+widget(xx+'+'+str(len(key)*8+8),yy,2,label=lab1)
  w+=widget(xx+'+'+str(len(key)*8+64),yy+6,1,'"/"')+widget(xx+'+'+str(len(key)*8+80),yy,2,label=40)+widget(xx+'+'+str(len(key)*8+132),yy,2,label=lab2)
 P.write_text(s.replace('// WIDGETS',w),encoding='utf8')
if __name__=='__main__':main()
