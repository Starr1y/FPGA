// 640x480 procedural UI. Two tiny ROMs and a frame-atomic status snapshot;
// no framebuffer and no audio-domain combinational path into pixels.
module duo04_panel(input clk,rst_n,input[1055:0]status,input status_update,
 output reg[7:0]red,green,blue,output reg hsync,vsync,de,output frame_request);
 reg[9:0]x,y,x1,y1,x2,y2;reg[1055:0]ui;
 wire[255:0]m=ui[1055:800];wire[1:0]page=m[3:2];
 assign frame_request=x==799 && y==479;
 reg[7:0]text_rom[0:4255];reg[19:0]font_rom[0:4159];
 initial begin $readmemh("rtl/duo04_text.hex",text_rom);$readmemh("rtl/duo04_font.hex",font_rom);end
 reg[7:0]glyph;reg[19:0]bits;reg[4:0]col1,row1,col2;
 wire[5:0]cell_x=x/20;wire[4:0]cell_y=y/20;
 reg[12:0]address;reg numeric;reg[15:0]number;reg[2:0]digit_position;
 // Decimal numbers use a shared constant-divisor formatter, not one per widget.
 function[3:0]decimal_digit;input[15:0]n;input[2:0]pos;
 begin case(pos)0:decimal_digit=(n/10000)%10;1:decimal_digit=(n/1000)%10;
  2:decimal_digit=(n/100)%10;3:decimal_digit=(n/10)%10;default:decimal_digit=n%10;endcase end
 endfunction
 // Generated ASCII digit glyph indices are supplied by the generator include.
 `include "rtl/duo04_digits.vh"
 always @*begin
  address=page*768+cell_y*32+cell_x;numeric=0;number=0;digit_position=cell_x[2:0];
  if(page==0)begin
   if(cell_y==4 && cell_x<8)address=3072+(24+m[1:0])*32+cell_x;
   if(cell_y==4 && cell_x>=16 && cell_x<24)address=3072+(m[10] ? 28 : 29)*32+cell_x-16;
   if(cell_y==8 && cell_x<8)address=3072+(20+m[98:96])*32+cell_x;
   if(cell_y==8 && cell_x>=16 && cell_x<24)address=3072+(20+m[101:99])*32+cell_x-16;
   if(cell_y==18 && (cell_x<5 || cell_x>=16 && cell_x<21))begin
    numeric=1;number=cell_x<16 ? {12'b0,ui[21:18]} : {12'b0,ui[277:274]};digit_position=cell_x<16 ? cell_x : cell_x-16;
   end
   if(cell_y==20 && (cell_x<5 || cell_x>=16 && cell_x<21))begin
    numeric=1;number=cell_x<16 ? {8'b0,ui[127:120]} : {8'b0,ui[383:376]};digit_position=cell_x<16 ? cell_x : cell_x-16;
   end
  end
  if(page==1)begin
   if(cell_y==5)address=3072+(m[8:4]<20 ? m[8:4] : 0)*32+cell_x;
   if(cell_y==7 && cell_x<5)begin numeric=1;number=m[31:16];digit_position=cell_x;end
  end
  if(page==2)begin
   if(cell_y==5 && cell_x<5)begin numeric=1;number={14'b0,m[33:32]};digit_position=cell_x;end
   if(cell_y==7 && cell_x<5)begin numeric=1;number={8'b0,m[47:40]};digit_position=cell_x;end
   if(cell_y==10 && cell_x<5)address=3072+(m[48] ? 31 : 30)*32+cell_x;
   if(cell_y==10 && cell_x>=10 && cell_x<15)begin numeric=1;number={12'b0,m[52:49]};digit_position=cell_x-10;end
   if(cell_y==10 && cell_x>=23 && cell_x<28)begin numeric=1;number={8'b0,m[63:56]};digit_position=cell_x-23;end
   if(cell_y==12 && cell_x<5)begin numeric=1;number=m[79:64];digit_position=cell_x;end
   if(cell_y==12 && cell_x>=16 && cell_x<21)begin numeric=1;number=m[95:80];digit_position=cell_x-16;end
   if(m[189] && cell_y==14)address=3072+34*32+cell_x;
  end
  if(page==3 && cell_y==3)begin
   if(cell_x<8)address=3072+(m[11] ? 32 : 33)*32+cell_x;
   if(cell_x>=16 && cell_x<24)address=3072+(m[12] ? 32 : 33)*32+cell_x-16;
  end
 end
 wire[3:0]digit=decimal_digit(number,digit_position);
 wire fan_hand=x>=320;wire[9:0]fan_base=fan_hand ? 328 : 32;
 wire[11:0]fan_zones;wire fan_boundary;reg[11:0]fan_zones2;reg fan_boundary2;
 duo_fan fans(.clk(clk),.rst_n(rst_n),.profile(fan_hand ? m[107:106] : m[105:104]),.col(x-fan_base),.row(y-200),
  .enabled(page==0 && x>=fan_base && x<fan_base+280 && y>=200 && y<340),.zones(fan_zones),.boundary(fan_boundary));
 wire rendered_hand=x2>=320;wire[255:0]hand_state=rendered_hand ? ui[511:256] : ui[255:0];
 wire sector_selected=hand_state[4] && |(fan_zones2 & (12'b1<<hand_state[21:18]));
 always @(posedge clk)begin fan_zones2<=fan_zones;fan_boundary2<=fan_boundary;end
 reg[23:0]rgb;
 always @*begin
  rgb=24'h0c1420;
  if(y2<56)rgb=24'h182a3e;
  if(page==0 && y2>=120 && y2<340)rgb=x2<320 ? 24'h102c38 : 24'h302238;
  if(page==0 && |fan_zones2)rgb=sector_selected ? (rendered_hand ? 24'h713959 : 24'h176960) : 24'h1b3145;
  if(page==0 && fan_boundary2)rgb=24'h78a5bc;
  if(y2==56)rgb=24'h30516a;
  if(page==1 && y2>=100 && y2<160)rgb=m[9] ? 24'h1a554b : 24'h233b50;
  if(page==2 && y2>=180 && y2<220)rgb=m[48] ? 24'h49314e : 24'h16504e;
  if(col2<20 && bits[19-col2])rgb=x2<320 ? 24'h6de3d2 : 24'hf0b2dc;
 end
 always @(posedge clk)begin
  if(!rst_n)begin x<=0;y<=0;x1<=0;y1<=0;x2<=0;y2<=0;ui<=0;glyph<=0;bits<=0;col1<=0;row1<=0;col2<=0;red<=0;green<=0;blue<=0;de<=0;hsync<=1;vsync<=1;end
  else begin
   if(x==799)begin x<=0;y<=y==524 ? 0 : y+1'b1;end else x<=x+1'b1;
   if(status_update)ui<=status;
   glyph<=x<640 && y<480 ? (numeric ? digit_glyph(digit) : text_rom[address]) : 0;
   col1<=x%20;row1<=y%20;x1<=x;y1<=y;
   bits<=font_rom[glyph*20+row1];col2<=col1;x2<=x1;y2<=y1;
   {red,green,blue}<=rgb;de<=x2<640 && y2<480;
   hsync<=!(x2>=656 && x2<752);vsync<=!(y2>=490 && y2<492);
  end
 end
endmodule
