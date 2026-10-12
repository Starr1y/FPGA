// Configuration view only. Input is an atomic frame snapshot from the menu core.
// 640x480 / 25MHz, shared WenKai ROM, no framebuffer or added clock domain.
module menu_panel(input clk,rst_n,input[63:0]status,input status_update,
 output reg[7:0]red,green,blue,output reg hsync,vsync,de,output frame_request);
 `include "rtl/menu_labels.vh"
 // status: page3:0,edit4,focus5,mute6,chord7,presets11:8,tails15:12,
 // layouts19:16,fx21:20,wet29:22,delay43:30,feedback51:44,depth59:52,visible60.
 reg[63:0]ui;reg[9:0]x,y,xp,yp;
 assign frame_request=x==799 && y==479;
 always @(posedge clk)begin
  if(!rst_n)begin ui<=0;x<=0;y<=0;xp<=0;yp<=0;end
  else begin
   xp<=x;yp<=y;
   if(x==799)begin x<=0;y<=y==524 ? 0 : y+1'b1;end else x<=x+1'b1;
   if(status_update)ui<=status;
  end
 end
 // Format four decimal values in blanking. 48-sample division uses bounded
 // subtraction (<=342 clocks), avoiding a hardware divider in the pixel path.
 reg[15:0]bcd[0:3];reg[1:0]number;reg[2:0]format_state;reg[4:0]shift;
 reg[13:0]remainder;reg[15:0]quotient,value;reg[31:0]word,adjusted;integer k;
 wire[15:0]wet_value={8'b0,ui[29:22]},feedback_value={8'b0,ui[51:44]};
 wire[15:0]wet_times100=(wet_value<<6)+(wet_value<<5)+(wet_value<<2);
 wire[15:0]feedback_times100=(feedback_value<<6)+(feedback_value<<5)+(feedback_value<<2);
 always @*begin
  adjusted=word;
  for(k=4;k<8;k=k+1)if(adjusted[k*4+:4]>=5)adjusted[k*4+:4]=adjusted[k*4+:4]+3;
 end
 always @(posedge clk)begin
  if(!rst_n)begin number<=0;format_state<=0;shift<=0;remainder<=0;quotient<=0;value<=0;word<=0;for(k=0;k<4;k=k+1)bcd[k]<=0;end
  else if(status_update)begin number<=0;format_state<=1;end
  else case(format_state)
   1:if(number==0)begin remainder<=ui[43:30];quotient<=0;format_state<=2;end
     else begin value<=number==1 ? wet_times100>>8 : number==2 ? feedback_times100>>8 : {8'b0,ui[59:52]};format_state<=3;end
   2:if(remainder>=48)begin remainder<=remainder-48;quotient<=quotient+1'b1;end
     else begin value<=quotient;format_state<=3;end
   3:begin word<={16'b0,value};shift<=0;format_state<=4;end
   4:begin word<=adjusted<<1;
    if(shift==15)begin bcd[number]<=adjusted[30:15];if(number==3)format_state<=0;else begin number<=number+1'b1;format_state<=1;end end
    else shift<=shift+1'b1;
   end
   default:format_state<=0;
  endcase
 end
 function[23:0]decimal3(input[1:0]id);
  begin decimal3={bcd[id][11:8]==0 ? 8'd32 : 8'd48+{4'b0,bcd[id][11:8]},
   bcd[id][11:4]==0 ? 8'd32 : 8'd48+{4'b0,bcd[id][7:4]},8'd48+{4'b0,bcd[id][3:0]}};end
 endfunction
 reg[3:0]row;reg[9:0]row_y;wire[9:0]wide_row={6'b0,row};
 always @*begin
  if(y<130)row=0;else if(y<156)row=1;else if(y<182)row=2;else if(y<208)row=3;
  else if(y<234)row=4;else if(y<260)row=5;else if(y<286)row=6;else if(y<312)row=7;
  else if(y<338)row=8;else if(y<364)row=9;else row=10;
  row_y=10'd104+(wide_row<<4)+(wide_row<<3)+(wide_row<<1);
 end
 reg[5:0]row_label,value_label,unit_label;reg[2:0]row_len,value_len,unit_len;
 reg[23:0]digits;reg numeric,percent,read_only;
 wire[1:0]preset=ui[5] ? ui[11:10] : ui[9:8];
 wire[1:0]tail=ui[5] ? ui[15:14] : ui[13:12];
 wire[1:0]layout=ui[5] ? ui[19:18] : ui[17:16];
 always @*begin
  row_label=L_UNKNOWN;row_len=2;value_label=L_UNKNOWN;value_len=2;unit_label=L_MS;unit_len=0;
  digits="---";numeric=0;percent=0;read_only=0;
  case(row)
   0:begin row_label=L_PAGE_FOCUS;row_len=3;value_label=ui[5] ? L_HAND_R : L_HAND_L;end
   1:begin row_label=L_PAGE_TIMBRE;value_label=preset==0 ? L_PLUCK : preset==1 ? L_BASS : preset==2 ? L_WIND : L_BELL;end
   2:begin row_label=L_PAGE_RELEASE;numeric=1;digits=tail==0 ? "200" : tail==1 ? "500" : tail==2 ? "1.5" : "---";
     unit_label=tail==2 ? L_SECOND : L_MS;unit_len=tail==2 ? 1 : 2;end
   3:begin row_label=L_PAGE_EFFECT;value_label=ui[21:20]==0 ? L_BYPASS : ui[21:20]==1 ? L_PAGE_DELAY : ui[21:20]==2 ? L_CHORUS : L_REVERB;end
   4:begin row_label=L_PAGE_WET;numeric=1;percent=1;digits=decimal3(1);end
   5:begin row_label=L_PAGE_DELAY;numeric=1;digits=decimal3(0);unit_label=L_MS;unit_len=2;end
   6:begin row_label=L_PAGE_FEEDBACK;
     if(ui[21:20]==2)begin value_label=L_FIXED_ZERO;value_len=3;read_only=1;end
     else begin numeric=1;percent=1;digits=decimal3(2);end
    end
   7:begin row_label=L_PAGE_DEPTH;row_len=4;numeric=1;digits=decimal3(3);unit_label=L_SAMPLES;unit_len=2;end
   8:begin row_label=L_PAGE_MODE;row_len=4;value_label=ui[7] ? L_CHORD : L_MELODIES;value_len=ui[7] ? 4 : 3;end
   9:begin row_label=L_PAGE_MUTE;value_label=ui[6] ? L_ON : L_OFF;end
   10:begin row_label=L_PAGE_LAYOUT;row_len=4;value_label=layout==0 ? L_SEVEN : layout==1 ? L_FIVE : layout==2 ? L_TWELVE : L_UNKNOWN;
     value_len=layout==2 ? 4 : 2;end
  endcase
 end
 wire[9:0]rl={7'b0,row_len},vl={7'b0,value_len},ul={7'b0,unit_len};
 wire[9:0]row_span=(rl<<4)+(rl<<3)+(rl<<1),value_span=(vl<<4)+(vl<<3)+(vl<<1),unit_span=(ul<<4)+(ul<<3)+(ul<<1);
 reg[9:0]tx,ty;reg[2:0]length;reg[5:0]label_id;reg[23:0]text;reg zh;reg[1:0]ink;
 always @*begin
  tx=0;ty=0;length=0;label_id=L_UNKNOWN;text="   ";zh=1;ink=1;
  if(ui[60])begin
   if(x>=32 && x<136 && y>=28 && y<52)begin tx=32;ty=28;length=4;label_id=L_TITLE;end
   if(x>=400 && x<452 && y>=28 && y<52)begin tx=400;ty=28;length=2;label_id=ui[5] ? L_HAND_R : L_HAND_L;end
   if(x>=536 && x<588 && y>=28 && y<52)begin tx=536;ty=28;length=2;label_id=ui[4] ? L_EDIT : L_SELECT;ink=ui[4] ? 2 : 1;end
   if(x>=32 && x<162 && y>=60 && y<84)begin tx=32;ty=60;length=5;
    label_id=ui[3:0]==1 || ui[3:0]==2 || ui[3:0]==10 ? L_HAND_SETTINGS : L_GLOBAL_SETTINGS;end
   if(y>=104 && y<390 && y<row_y+24)begin
    ink=row==ui[3:0] ? 1 : 3;
    if(x>=56 && x<56+row_span)begin tx=56;ty=row_y;length=row_len;label_id=row_label;end
    if(!numeric && x>=400 && x<400+value_span)begin tx=400;ty=row_y;length=value_len;label_id=value_label;
     if(read_only)ink=3;else if(row==ui[3:0] && ui[4])ink=2;end
    if(numeric && x>=456 && x<495)begin tx=456;ty=row_y;length=3;zh=0;text=digits;if(row==ui[3:0] && ui[4])ink=2;end
    if(unit_len!=0 && x>=512 && x<512+unit_span)begin tx=512;ty=row_y;length=unit_len;label_id=unit_label;end
    if(percent && x>=512 && x<525)begin tx=512;ty=row_y;length=1;zh=0;text="%";end
   end
   if(x>=32 && x<136 && y>=414 && y<438)begin tx=32;ty=414;length=4;label_id=ui[4] ? L_ROTATE_EDIT : L_ROTATE;end
   if(x>=224 && x<328 && y>=414 && y<438)begin tx=224;ty=414;length=4;label_id=ui[4] ? L_CLICK_EDIT : L_CLICK;end
   if(x>=448 && x<552 && y>=414 && y<438)begin tx=448;ty=414;length=4;label_id=L_BACK;end
  end
 end
 wire[9:0]offset=x-tx;
 wire[4:0]zh_position=offset>=104 ? 4 : offset>=78 ? 3 : offset>=52 ? 2 : offset>=26 ? 1 : 0;
 wire[9:0]zh_start=offset>=104 ? 104 : offset>=78 ? 78 : offset>=52 ? 52 : offset>=26 ? 26 : 0;
 wire[4:0]zh_column=offset-zh_start;
 wire[4:0]ascii_position=offset>=26 ? 2 : offset>=13 ? 1 : 0;
 wire[9:0]ascii_start=offset>=26 ? 26 : offset>=13 ? 13 : 0;
 wire[4:0]ascii_column=offset-ascii_start;
 wire[7:0]ch=ascii_position<length ? text[((length-ascii_position-1)<<3)+:8] : 8'd32;
 wire[4:0]font_row=y-ty;wire[6:0]glyph;wire[23:0]font_bits;wire[12:0]ascii_bits;
 wire[9:0]len_wide={7'b0,length};
 wire[9:0]text_span=zh ? (len_wide<<4)+(len_wide<<3)+(len_wide<<1) : (len_wide<<3)+(len_wide<<2)+len_wide;
 wire text_valid=length!=0 && x>=tx && y>=ty && x<tx+text_span && y<ty+24;
 menu_labels labels(.label_id(label_id),.position(zh_position),.glyph(glyph));
 menu_font font(.clk(clk),.enabled(rst_n && text_valid && zh),.glyph(glyph),.row(font_row),.bits(font_bits));
 menu_ascii ascii_font(.clk(clk),.enabled(rst_n && text_valid && !zh),.ch(ch),.row(font_row),.bits(ascii_bits));
 reg text_p,zh_p,selected_p;reg[4:0]column_p;reg[1:0]ink_p;
 always @(posedge clk)begin
  text_p<=rst_n && text_valid;zh_p<=zh;ink_p<=ink;
  column_p<=zh ? zh_column : ascii_column;
  selected_p<=ui[60] && y>=104 && y<390 && y<row_y+24 && row==ui[3:0];
 end
 wire text_pixel=text_p && (zh_p ? (column_p<24 && font_bits[23-column_p]) : (column_p<13 && ascii_bits[12-column_p]));
 reg[23:0]rgb;
 always @*begin
  rgb=yp[1:0]==0 ? 24'h080010 : 24'h0a0014;
  if(ui[60])begin
   if(selected_p && xp>=32 && xp<608)rgb=24'h11102a;
   if(selected_p && xp>=32 && xp<35)rgb=ui[4] ? 24'hff006e : 24'h00ffff;
   if(yp==86 && xp>=32 && xp<608)rgb=24'hff006e;
   if(text_pixel)rgb=ink_p==2 ? 24'hff006e : ink_p==3 ? 24'h8294a6 : 24'h00ffff;
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin red<=0;green<=0;blue<=0;hsync<=1;vsync<=1;de<=0;end
  else begin {red,green,blue}<=rgb;de<=xp<640 && yp<480;
   hsync<=!(xp>=656 && xp<752);vsync<=!(yp>=490 && yp<492);end
 end
endmodule
