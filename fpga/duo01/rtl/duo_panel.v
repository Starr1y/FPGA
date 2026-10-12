// Two independent 180-degree fans. Geometry and WenKai ROM are shared per pixel.
// Measured telemetry is captured in vertical blank and hidden on the main page.
module duo_panel(input clk,rst_n,input[767:0]status,input status_update,
 output reg[7:0]red,green,blue,output reg hsync,vsync,de,output frame_request);
 reg[9:0]x,y,xp,yp;reg[767:0]ui;
 assign frame_request=x==799 && y==479;
 always @(posedge clk)begin
  if(!rst_n)begin x<=0;y<=0;xp<=0;yp<=0;ui<=0;end
  else begin
   if(x==799)begin x<=0;y<=y==524 ? 0 : y+1'b1;end else x<=x+1'b1;
   xp<=x;yp<=y;if(status_update)ui<=status;
  end
 end
 wire hand=x>=320;wire[9:0]base=hand ? 328 : 32;wire[8:0]col=x-base;
 wire[255:0]s=hand ? ui[511:256] : ui[255:0];
 wire[1:0]profile=hand ? ui[515:514] : ui[513:512];
 wire[1:0]preset=hand ? ui[519:518] : ui[517:516];
 wire enabled=ui[520+hand],focused=hand==ui[522],diag=ui[523];
 reg[23:0]flash[0:1];reg[31:0]old_hits[0:1];integer h;
 always @(posedge clk)begin
  if(!rst_n)for(h=0;h<2;h=h+1)begin flash[h]<=0;old_hits[h]<=0;end
  else for(h=0;h<2;h=h+1)begin
   if(flash[h]!=0)flash[h]<=flash[h]-1'b1;
   if(status_update)begin
    old_hits[h]<=status[h*256+128+:32];
    if(!status[520+h] || !status[h*256] || status[h*256+31] || status[h*256+128+:32]<old_hits[h])flash[h]<=0;
    else if(status[h*256+128+:32]>old_hits[h])flash[h]<=3750000;
   end
  end
 end
 // One sequential binary-to-decimal formatter: 3 angles + bounded hit count/hand.
 reg[15:0]bcd[0:7];reg[3:0]num;reg[4:0]shift;reg[1:0]fmt;
 reg[31:0]word,adjusted;reg[15:0]value;reg signed[15:0]angle;integer k;
 always @* begin
  angle=ui[(num[2] ? 256 : 0)+32+num[1:0]*16+:16];
  value=(angle[15] ? -angle : angle);value=(value+8)>>4;
  if(num[1:0]==3)value=ui[(num[2] ? 256 : 0)+128+:32]>9999 ? 9999 : ui[(num[2] ? 256 : 0)+128+:16];
  adjusted=word;for(k=4;k<8;k=k+1)if(adjusted[k*4+:4]>=5)adjusted[k*4+:4]=adjusted[k*4+:4]+3;
 end
 always @(posedge clk)begin
  if(!rst_n)begin num<=0;shift<=0;fmt<=0;word<=0;for(k=0;k<8;k=k+1)bcd[k]<=0;end
  else if(status_update)begin num<=0;fmt<=1;end
  else case(fmt)
   1:begin word<={16'b0,value};shift<=0;fmt<=2;end
   2:begin word<=adjusted<<1;
    if(shift==15)begin bcd[num]<=adjusted[30:15];if(num==7)fmt<=0;else begin num<=num+1'b1;fmt<=1;end end
    else shift<=shift+1'b1;
   end
  endcase
 end
 function[7:0]digit;input[3:0]id;input[1:0]position;
 begin digit="0"+((bcd[id]>>(12-position*4))&15);end endfunction
 function[7:0]hexchar;input[3:0]n;begin hexchar=n<10 ? "0"+n : "A"+n-10;end endfunction
 function[31:0]hex4;input[15:0]v;begin hex4={hexchar(v[15:12]),hexchar(v[11:8]),hexchar(v[7:4]),hexchar(v[3:0])};end endfunction
 function[63:0]hex8;input[31:0]v;begin hex8={hex4(v[31:16]),hex4(v[15:0])};end endfunction
 function[31:0]note;input[1:0]p;input[3:0]z;
 begin case(p)
  0:case(z)0:note="DO  ";1:note="RE  ";2:note="MI  ";3:note="FA  ";4:note="SOL ";5:note="LA  ";6:note="SI  ";default:note="----";endcase
  1:case(z)0:note="DO  ";1:note="RE  ";2:note="MI  ";3:note="SOL ";4:note="LA  ";default:note="----";endcase
  2:case(z)0:note="DO  ";1:note="DO# ";2:note="RE  ";3:note="RE# ";4:note="MI  ";5:note="FA  ";6:note="FA# ";7:note="SOL ";8:note="SOL#";9:note="LA  ";10:note="LA# ";11:note="SI  ";default:note="----";endcase
  default:note="----";
 endcase end endfunction
 reg[5:0]state_label;
 always @*begin
  state_label=13;
  if(!enabled)state_label=7;else if(s[31])state_label=42;else if(!s[0])state_label=8;
  else if(s[2])state_label=9;else if(!s[1])state_label=10;
  else if(s[9:8]<2)state_label=12;else if(s[5] || !s[7])state_label=11;
  else if(s[30])state_label=14;
 end
 // Widget selection drives a shared synchronous font lookup.
 reg zh,doubled;reg[5:0]label_id,text_len;reg[9:0]tx,ty;reg[255:0]text;reg[1:0]ink;
 always @*begin
  zh=0;doubled=0;label_id=0;text_len=0;tx=0;ty=0;text=0;ink=1;
  if(x>=32 && x<(32)+7*16 && y>=28 && y<52)begin zh=0;doubled=1;tx=32;ty=28;text_len=7;ink=1;text="TANGLAB";end
if(x>=176 && x<(176)+4*26 && y>=28 && y<52)begin zh=1;doubled=0;tx=176;ty=28;text_len=4;ink=1;label_id=0;end
if(x>=372 && x<(372)+4*26 && y>=28 && y<52)begin zh=1;doubled=0;tx=372;ty=28;text_len=4;ink=1;label_id=ui[525] ? 31 : 30;end
if(x>=548 && x<(548)+2*26 && y>=28 && y<52)begin zh=1;doubled=0;tx=548;ty=28;text_len=2;ink=2;label_id=ui[524] ? 3 : 4;end
if(x>=32 && x<(32)+5*8 && y>=68 && y<80)begin zh=0;doubled=0;tx=32;ty=68;text_len=5;ink=1;text="DUO01";end
if(x>=192 && x<(192)+2*26 && y>=60 && y<84)begin zh=1;doubled=0;tx=192;ty=60;text_len=2;ink=1;label_id=diag ? 6 : 5;end
if(x>=328 && x<(328)+17*8 && y>=68 && y<80)begin zh=0;doubled=0;tx=328;ty=68;text_len=17;ink=1;text="I2C / 32 VOICE   ";end
if(x>=552 && x<(552)+4*8 && y>=68 && y<80)begin zh=0;doubled=0;tx=552;ty=68;text_len=4;ink=1;text=ui[522] ? "R   " : "L   ";end
if(x>=base+8 && x<(base+8)+2*26 && y>=112 && y<136)begin zh=1;doubled=0;tx=base+8;ty=112;text_len=2;ink=1;label_id=hand ? 2 : 1;end
if(x>=base+120 && x<(base+120)+5*26 && y>=112 && y<136)begin zh=1;doubled=0;tx=base+120;ty=112;text_len=5;ink=state_label==13 ? 1 : 2;label_id=state_label;end
if(x>=base+8 && x<(base+8)+3*26 && y>=156 && y<180)begin zh=1;doubled=0;tx=base+8;ty=156;text_len=3;ink=1;label_id=profile==1 ? 16 : profile==2 ? 17 : 15;end
if(x>=base+174 && x<(base+174)+2*26 && y>=156 && y<180)begin zh=1;doubled=0;tx=base+174;ty=156;text_len=2;ink=1;label_id=18+preset;end
if(!diag)begin
if(profile==0)begin
if(col>=23 && col<39 && y>=308 && y<320)begin text="DO";text_len=2;tx=base+23;ty=308;end
if(col>=44 && col<60 && y>=263 && y<275)begin text="RE";text_len=2;tx=base+44;ty=263;end
if(col>=83 && col<99 && y>=232 && y<244)begin text="MI";text_len=2;tx=base+83;ty=232;end
if(col>=132 && col<148 && y>=221 && y<233)begin text="FA";text_len=2;tx=base+132;ty=221;end
if(col>=177 && col<201 && y>=232 && y<244)begin text="SOL";text_len=3;tx=base+177;ty=232;end
if(col>=220 && col<236 && y>=263 && y<275)begin text="LA";text_len=2;tx=base+220;ty=263;end
if(col>=241 && col<257 && y>=308 && y<320)begin text="SI";text_len=2;tx=base+241;ty=308;end
end
if(profile==1)begin
if(col>=25 && col<41 && y>=298 && y<310)begin text="DO";text_len=2;tx=base+25;ty=298;end
if(col>=66 && col<82 && y>=242 && y<254)begin text="RE";text_len=2;tx=base+66;ty=242;end
if(col>=132 && col<148 && y>=221 && y<233)begin text="MI";text_len=2;tx=base+132;ty=221;end
if(col>=194 && col<218 && y>=242 && y<254)begin text="SOL";text_len=3;tx=base+194;ty=242;end
if(col>=239 && col<255 && y>=298 && y<310)begin text="LA";text_len=2;tx=base+239;ty=298;end
end
if(profile==2)begin
if(col>=21 && col<37 && y>=318 && y<330)begin text="DO";text_len=2;tx=base+21;ty=318;end
if(col>=25 && col<49 && y>=290 && y<302)begin text="DO#";text_len=3;tx=base+25;ty=290;end
if(col>=43 && col<59 && y>=265 && y<277)begin text="RE";text_len=2;tx=base+43;ty=265;end
if(col>=60 && col<84 && y>=244 && y<256)begin text="RE#";text_len=3;tx=base+60;ty=244;end
if(col>=89 && col<105 && y>=230 && y<242)begin text="MI";text_len=2;tx=base+89;ty=230;end
if(col>=117 && col<133 && y>=222 && y<234)begin text="FA";text_len=2;tx=base+117;ty=222;end
if(col>=143 && col<167 && y>=222 && y<234)begin text="FA#";text_len=3;tx=base+143;ty=222;end
if(col>=171 && col<195 && y>=230 && y<242)begin text="SOL";text_len=3;tx=base+171;ty=230;end
if(col>=192 && col<224 && y>=244 && y<256)begin text="SOL#";text_len=4;tx=base+192;ty=244;end
if(col>=221 && col<237 && y>=265 && y<277)begin text="LA";text_len=2;tx=base+221;ty=265;end
if(col>=231 && col<255 && y>=290 && y<302)begin text="LA#";text_len=3;tx=base+231;ty=290;end
if(col>=243 && col<259 && y>=318 && y<330)begin text="SI";text_len=2;tx=base+243;ty=318;end
end

if(x>=base+8 && x<(base+8)+2*26 && y>=356 && y<380)begin zh=1;doubled=0;tx=base+8;ty=356;text_len=2;ink=1;label_id=22;end
if(x>=base+64 && x<(base+64)+4*16 && y>=356 && y<380)begin zh=0;doubled=1;tx=base+64;ty=356;text_len=4;ink=1;text=s[4] ? note(profile,s[21:18]) : "----";end
if(x>=base+136 && x<(base+136)+2*26 && y>=356 && y<380)begin zh=1;doubled=0;tx=base+136;ty=356;text_len=2;ink=2;label_id=23;end
if(x>=base+192 && x<(base+192)+4*16 && y>=356 && y<380)begin zh=0;doubled=1;tx=base+192;ty=356;text_len=4;ink=2;text=s[159:128]!=0 ? note(s[27:26],s[25:22]) : "----";end
end else begin
if(x>=base+8 && x<(base+8)+2*26 && y>=200 && y<224)begin zh=1;doubled=0;tx=base+8;ty=200;text_len=2;ink=1;label_id=26;end
if(x>=base+100 && x<(base+100)+4*16 && y>=200 && y<224)begin zh=0;doubled=1;tx=base+100;ty=200;text_len=4;ink=1;text={(s[47] ? "-" : "+"),digit((hand ? 4 : 0)+0,1),digit((hand ? 4 : 0)+0,2),digit((hand ? 4 : 0)+0,3)};end
if(x>=base+8 && x<(base+8)+2*26 && y>=238 && y<262)begin zh=1;doubled=0;tx=base+8;ty=238;text_len=2;ink=1;label_id=27;end
if(x>=base+100 && x<(base+100)+4*16 && y>=238 && y<262)begin zh=0;doubled=1;tx=base+100;ty=238;text_len=4;ink=1;text={(s[63] ? "-" : "+"),digit((hand ? 4 : 0)+1,1),digit((hand ? 4 : 0)+1,2),digit((hand ? 4 : 0)+1,3)};end
if(x>=base+8 && x<(base+8)+2*26 && y>=276 && y<300)begin zh=1;doubled=0;tx=base+8;ty=276;text_len=2;ink=1;label_id=28;end
if(x>=base+100 && x<(base+100)+4*16 && y>=276 && y<300)begin zh=0;doubled=1;tx=base+100;ty=276;text_len=4;ink=1;text={(s[79] ? "-" : "+"),digit((hand ? 4 : 0)+2,1),digit((hand ? 4 : 0)+2,2),digit((hand ? 4 : 0)+2,3)};end
if(x>=base+8 && x<(base+8)+20*8 && y>=316 && y<328)begin zh=0;doubled=0;tx=base+8;ty=316;text_len=20;ink=1;text={"RX ",hex4(s[191:176])," PKT ",hex4(s[175:160]),"    "};end
if(x>=base+8 && x<(base+8)+12*8 && y>=336 && y<348)begin zh=0;doubled=0;tx=base+8;ty=336;text_len=12;ink=2;text={"ERR ",hex8(s[223:192])};end
if(x>=base+160 && x<(base+160)+8*8 && y>=336 && y<348)begin zh=0;doubled=0;tx=base+160;ty=336;text_len=8;ink=2;text={"RST ",hex4(s[239:224])};end
if(x>=base+8 && x<(base+8)+23*8 && y>=356 && y<368)begin zh=0;doubled=0;tx=base+8;ty=356;text_len=23;ink=1;text={"HZ P",hex4(ui[640+hand*48+:16])," A",hex4(ui[656+hand*48+:16])," G",hex4(ui[672+hand*48+:16]),"   "};end
if(x>=base+8 && x<(base+8)+8*8 && y>=376 && y<388)begin zh=0;doubled=0;tx=base+8;ty=376;text_len=8;ink=1;text={"QUAL ",("0"+{6'b0,s[9:8]}),"/3"};end
if(x>=base+160 && x<(base+160)+9*8 && y>=376 && y<388)begin zh=0;doubled=0;tx=base+160;ty=376;text_len=9;ink=1;text={"HIT ",digit(hand ? 7 : 3,0),digit(hand ? 7 : 3,1),digit(hand ? 7 : 3,2),digit(hand ? 7 : 3,3)," "};end
end
if(x>=32 && x<(32)+4*8 && y>=420 && y<432)begin zh=0;doubled=0;tx=32;ty=420;text_len=4;ink=1;text="KEY0";end
if(x>=32+40 && x<(32+40)+2*26 && y>=414 && y<438)begin zh=1;doubled=0;tx=32+40;ty=414;text_len=2;ink=1;label_id=33;end
if(x>=32+96 && x<(32+96)+1*8 && y>=420 && y<432)begin zh=0;doubled=0;tx=32+96;ty=420;text_len=1;ink=1;text="/";end
if(x>=32+112 && x<(32+112)+2*26 && y>=414 && y<438)begin zh=1;doubled=0;tx=32+112;ty=414;text_len=2;ink=1;label_id=40;end
if(x>=32+164 && x<(32+164)+2*26 && y>=414 && y<438)begin zh=1;doubled=0;tx=32+164;ty=414;text_len=2;ink=1;label_id=34;end
if(x>=328 && x<(328)+4*8 && y>=420 && y<432)begin zh=0;doubled=0;tx=328;ty=420;text_len=4;ink=1;text="KEY2";end
if(x>=328+40 && x<(328+40)+2*26 && y>=414 && y<438)begin zh=1;doubled=0;tx=328+40;ty=414;text_len=2;ink=1;label_id=32;end
if(x>=328+96 && x<(328+96)+1*8 && y>=420 && y<432)begin zh=0;doubled=0;tx=328+96;ty=420;text_len=1;ink=1;text="/";end
if(x>=328+112 && x<(328+112)+2*26 && y>=414 && y<438)begin zh=1;doubled=0;tx=328+112;ty=414;text_len=2;ink=1;label_id=40;end
if(x>=328+164 && x<(328+164)+2*26 && y>=414 && y<438)begin zh=1;doubled=0;tx=328+164;ty=414;text_len=2;ink=1;label_id=36;end
if(x>=32 && x<(32)+4*8 && y>=450 && y<462)begin zh=0;doubled=0;tx=32;ty=450;text_len=4;ink=1;text="KEY1";end
if(x>=32+40 && x<(32+40)+2*26 && y>=444 && y<468)begin zh=1;doubled=0;tx=32+40;ty=444;text_len=2;ink=1;label_id=35;end
if(x>=32+96 && x<(32+96)+1*8 && y>=450 && y<462)begin zh=0;doubled=0;tx=32+96;ty=450;text_len=1;ink=1;text="/";end
if(x>=32+112 && x<(32+112)+2*26 && y>=444 && y<468)begin zh=1;doubled=0;tx=32+112;ty=444;text_len=2;ink=1;label_id=40;end
if(x>=32+164 && x<(32+164)+2*26 && y>=444 && y<468)begin zh=1;doubled=0;tx=32+164;ty=444;text_len=2;ink=1;label_id=14;end
if(x>=328 && x<(328)+6*8 && y>=450 && y<462)begin zh=0;doubled=0;tx=328;ty=450;text_len=6;ink=1;text="KEY1+2";end
if(x>=328+56 && x<(328+56)+2*26 && y>=444 && y<468)begin zh=1;doubled=0;tx=328+56;ty=444;text_len=2;ink=1;label_id=6;end
if(x>=328+112 && x<(328+112)+1*8 && y>=450 && y<462)begin zh=0;doubled=0;tx=328+112;ty=450;text_len=1;ink=1;text="/";end
if(x>=328+128 && x<(328+128)+2*26 && y>=444 && y<468)begin zh=1;doubled=0;tx=328+128;ty=444;text_len=2;ink=1;label_id=40;end
if(x>=328+180 && x<(328+180)+2*26 && y>=444 && y<468)begin zh=1;doubled=0;tx=328+180;ty=444;text_len=2;ink=1;label_id=37;end

 end
 wire[9:0]offset=x-tx;
 wire[4:0]zh_pos=offset>=104 ? 4 : offset>=78 ? 3 : offset>=52 ? 2 : offset>=26 ? 1 : 0;
 wire[9:0]zh_start=offset>=104 ? 104 : offset>=78 ? 78 : offset>=52 ? 52 : offset>=26 ? 26 : 0;
 wire[4:0]zh_col=offset-zh_start;
 wire[5:0]ascii_pos=doubled ? offset>>4 : offset>>3;
 wire[7:0]ch=ascii_pos<text_len ? text[(text_len-ascii_pos-1)*8+:8] : 8'd32;
 wire[3:0]ascii_row=doubled ? (y-ty)>>1 : y-ty;
 wire[4:0]font_row=y-ty;wire[6:0]glyph;wire[23:0]zh_bits;wire[7:0]ascii_bits;
 duo_text labels(.label_id(label_id),.position(zh_pos),.glyph(glyph));
 duo_font font(.clk(clk),.glyph(glyph),.row(font_row),.bits(zh_bits));
 video_font ascii_font(.ch(ch),.row(ascii_row),.bits(ascii_bits));
 wire text_valid=text_len!=0 && x>=tx && y>=ty &&
  x<tx+text_len*(zh ? 26 : doubled ? 16 : 8) && y<ty+(zh || doubled ? 24 : 12);
 reg text_p,zh_p;reg[4:0]column_p;reg[7:0]ascii_p;reg[1:0]ink_p;
 always @(posedge clk)begin
  text_p<=rst_n && text_valid;zh_p<=zh;ink_p<=ink;ascii_p<=ascii_bits;
  column_p<=zh ? zh_col : doubled ? offset[3:1] : offset[2:0];
 end
 wire text_pixel=text_p && (zh_p ? (column_p<24 && zh_bits[23-column_p]) : ascii_p[7-column_p]);
 wire[11:0]zones;wire fan_edge;
 duo_fan fan(.clk(clk),.rst_n(rst_n),.profile(profile),.col(col),.row(y-200),
  .enabled(!diag && x>=base && x<base+280 && y>=200 && y<340),.zones(zones),.boundary(fan_edge));
 wire hp=xp>=320;wire[9:0]bp=hp ? 328 : 32;
 wire[255:0]sp=hp ? ui[511:256] : ui[255:0];
 wire selected=ui[520+hp] && sp[0] && !sp[31] && sp[4] && |(zones & (12'b1<<sp[21:18]));
 wire hit=ui[520+hp] && sp[0] && !sp[31] && sp[159:128]!=0 && sp[27:26]==(hp ? ui[515:514] : ui[513:512]) && flash[hp]!=0 && |(zones & (12'b1<<sp[25:22]));
 wire border=(xp==bp || xp==bp+279) && yp>=100 && yp<=398 ||
  (yp==100 || yp==398) && xp>=bp && xp<=bp+279;
 reg[23:0]rgb;
 always @*begin
  rgb=yp[1:0]==0 ? 24'h080010 : 24'h0a0014;
  if(border)rgb=hp==ui[522] ? 24'h00ffff : 24'h283448;
  if(!diag && |zones)begin rgb=24'h11102a;
   if(selected)rgb=24'h004750;
   if(hit)rgb=24'h63002d;
   if(fan_edge)rgb=hit ? 24'hff006e : selected ? 24'h00ffff : 24'h244858;
  end
  if(xp>=32 && xp<608 && yp==86)rgb=24'hff006e;
  if(xp>=bp+8 && xp<bp+8+sp[127:120] && yp>=391 && yp<394)rgb=24'hff006e;
  if(text_pixel)rgb=ink_p==2 ? 24'hff006e : ink_p==3 ? 24'h8294a6 : 24'h00ffff;
 end
 always @(posedge clk)begin
  if(!rst_n)begin red<=0;green<=0;blue<=0;de<=0;hsync<=1;vsync<=1;end
  else begin {red,green,blue}<=rgb;de<=xp<640 && yp<480;
   hsync<=!(xp>=656 && xp<752);vsync<=!(yp>=490 && yp<492);end
 end
endmodule
