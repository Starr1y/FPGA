// 640x480 procedural UI. Two tiny ROMs and a frame-atomic status snapshot;
// no framebuffer and no audio-domain combinational path into pixels.
module duo04_panel(input clk,rst_n,input[1055:0]status,input status_update,
 output reg[7:0]red,green,blue,output reg hsync,vsync,de,output frame_request);
 reg[9:0]x,y,x1,y1,x2,y2;reg[1055:0]ui;
 reg[25:0]volume_timer;reg[8:0]seen_volume;
 wire[255:0]m=ui[1055:800];
 always @(posedge clk)begin
  if(!rst_n)begin volume_timer<=0;seen_volume<=0;end
  else if(m[128:120]!=seen_volume)begin seen_volume<=m[128:120];volume_timer<=26'd37500000;end
  else if(volume_timer!=0)volume_timer<=volume_timer-1'b1;
 end
 wire[1:0]page=m[3:2];
 assign frame_request=x==799 && y==479;
 reg[8:0]text_rom[0:8191];reg[19:0]font_rom[0:10239];
 initial begin $readmemh("rtl/duo04_text.hex",text_rom);$readmemh("rtl/duo04_font.hex",font_rom);end
 reg[8:0]glyph;reg[19:0]bits;reg[4:0]col1,row1,col2;
 wire[5:0]cell_x=x/20;wire[4:0]cell_y=y/20;
 reg small_text;reg[4:0]small_col,small_row;
 wire[9:0]local_label_x=x>=320 ? x-328 : x-32;wire[1:0]label_profile=x>=320 ? m[107:106] : m[105:104];
 reg[12:0]address;reg numeric;reg[15:0]number;reg[2:0]digit_position;
 // Decimal numbers use a shared constant-divisor formatter, not one per widget.
 function[3:0]decimal_digit;input[15:0]n;input[2:0]pos;
 begin case(pos)0:decimal_digit=(n/10000)%10;1:decimal_digit=(n/1000)%10;
  2:decimal_digit=(n/100)%10;3:decimal_digit=(n/10)%10;default:decimal_digit=n%10;endcase end
 endfunction
 // Generated ASCII digit glyph indices are supplied by the generator include.
 `include "rtl/duo04_digits.vh"
 wire perform=page==0 || page==2;
 wire[2:0]level=m[193:191];wire[3:0]item=m[200:197];wire[2:0]grp=m[196:194];
 function[4:0]field_at;input[2:0]g;input[3:0]n;
 begin case(g)
 0:case(n)0:field_at=1;1:field_at=3;2:field_at=5;3:field_at=11;default:field_at=13;endcase
 1:case(n)0:field_at=2;1:field_at=4;2:field_at=6;3:field_at=12;default:field_at=14;endcase
 2:field_at=n==0 ? 9 : 10;
 3:case(n)0:field_at=7;1:field_at=15;2:field_at=16;3:field_at=17;default:field_at=18;endcase
 4:field_at=n==0 ? 19 : n==1 ? 23 : 27;
 default:case(n)0:field_at=0;1:field_at=8;2:field_at=21;default:field_at=28;endcase
 endcase end endfunction
 reg[6:0]label_row;reg[4:0]row_field;reg[6:0]value_label;
 always @*begin
  address=page*768+cell_y*32+cell_x;numeric=0;number=0;digit_position=cell_x[2:0];label_row=0;small_text=0;small_col=0;small_row=0;row_field=0;value_label=0;
  if(perform)begin
   if(cell_y==4 && cell_x<8)address=3072+(m[190] ? 31 : 30)*32+cell_x;
   if(cell_y==4 && cell_x>=16 && cell_x<24)address=3072+(m[10] ? 28 : 29)*32+cell_x-16;
   if(cell_y==8 && cell_x<8)address=3072+(20+m[98:96])*32+cell_x;
   if(cell_y==8 && cell_x>=16 && cell_x<24)address=3072+(20+m[101:99])*32+cell_x-16;
   if(page==0 && cell_y==18 && (cell_x<5 || cell_x>=16 && cell_x<21))begin numeric=1;number=cell_x<16 ? {12'b0,ui[21:18]} : {12'b0,ui[277:274]};digit_position=cell_x<16 ? cell_x : cell_x-16;end
   if(page==0 && cell_y==20 && (cell_x<5 || cell_x>=16 && cell_x<21))begin numeric=1;number=cell_x<16 ? {8'b0,ui[127:120]} : {8'b0,ui[383:376]};digit_position=cell_x<16 ? cell_x : cell_x-16;end
   if(page==2)begin
    if(cell_y==4 && cell_x<8)address=3072+(m[48] ? 31 : 30)*32+cell_x;
    if(cell_y==4 && cell_x>=16 && cell_x<21)begin numeric=1;number={8'b0,m[47:40]};digit_position=cell_x-16;end
    if(cell_y==18 && (cell_x<5 || cell_x>=16 && cell_x<21))begin numeric=1;number=cell_x<16 ? m[79:64] : m[95:80];digit_position=cell_x<16 ? cell_x : cell_x-16;end
    if(m[189] && cell_y==20)address=3072+34*32+cell_x;
   end
  end
  if(page==1)begin
   if(cell_y>=5 && cell_y<=19 && cell_y[0])begin
    label_row=(cell_y-5)>>1;
    if(level==1 && label_row<5)address=3072+(40+label_row)*32+cell_x;
    else if(level==2 && label_row<6)address=3072+(45+label_row)*32+cell_x;
    else if(level>=3 && label_row<(grp==0 || grp==1 || grp==3 ? 5 : grp==5 ? 4 : grp==4 ? 3 : 2))begin row_field=field_at(grp,label_row[3:0]);address=3072+(row_field<20 ? row_field : row_field==23 ? 37 : row_field==21 ? 38 : row_field==27 ? 106 : 39)*32+cell_x;end
    else address=32;
   end
   if(cell_y==17 && level==5)address=3072+53*32+cell_x;
   if(level>=3 && cell_y==20 && cell_x<5)begin numeric=1;number=m[31:16];digit_position=cell_x;end
  end
  if(page==3)begin
   if(cell_y==4 && cell_x<8)address=3072+(m[11] ? 32 : 33)*32+cell_x;
   if(cell_y==4 && cell_x>=16 && cell_x<24)address=3072+(m[12] ? 32 : 33)*32+cell_x-16;
   if(cell_y==8)address=3072+(m[234:233]==1 ? 56 : m[234:233]==2 ? 57 : m[234:233]==3 ? 58 : 27)*32+cell_x;
  end
  if(page==1 && cell_y==21)address=32;
  if(page==1 && level>=3)begin
   if(cell_y==19)address=768+21*32+cell_x;
   if(cell_y==4)address=3072+(45+grp)*32+cell_x;
   case(m[8:4])
    0:value_label=24+m[31:16];
    1,2:value_label=20+m[31:16];
    3,4:value_label=86+m[31:16];
    5,6:value_label=89+m[31:16];
    7,15,16,17,18:value_label=93+m[31:16];
    13,14:value_label=95+m[31:16];
    19:value_label=98+m[31:16];
    23:value_label=m[16] ? 54 : 55;
    default:value_label=0;
   endcase
   if(cell_y==18)address=3072+(level==5 ? 103 : level==4 ? 102 : 101)*32+cell_x;
   if(cell_y==20 && cell_x>=8 && value_label!=0)address=3072+value_label*32+cell_x-8;
  end
  if(page==2 && m[232:225]==3 && cell_y==20)address=3072+59*32+cell_x;
  if(perform && volume_timer!=0 && cell_y==2)begin
   if(cell_x>=25 && cell_x<30)begin numeric=1;number=(m[128:120]*16'd100)>>8;digit_position=cell_x-25;end
   if(cell_x==30)address=3072+107*32;
  end
  `include "rtl/duo04_note_labels.vh"
 end
 wire[3:0]digit=decimal_digit(number,digit_position);
 wire leading_blank=numeric && (digit_position==0 && number<10000 || digit_position==1 && number<1000 || digit_position==2 && number<100 || digit_position==3 && number<10);
 wire fan_hand=x>=320;wire[9:0]fan_base=fan_hand ? 328 : 32;
 wire[8:0]fan_col=(x-fan_base);wire[8:0]fan_row=(y-200);wire[11:0]fan_zones;wire fan_boundary;reg[11:0]fan_zones2;reg fan_boundary2;
 duo_fan fans(.clk(clk),.rst_n(rst_n),.profile(fan_hand ? m[107:106] : m[105:104]),.col(fan_col),.row(fan_row),
  .enabled(perform && x>=fan_base && x<fan_base+280 && y>=200 && y<340),.zones(fan_zones),.boundary(fan_boundary));
 wire rendered_hand=x2>=320;wire[255:0]hand_state=rendered_hand ? ui[511:256] : ui[255:0];
 wire sector_selected=hand_state[4] && |(fan_zones2 & (12'b1<<hand_state[21:18]));
 always @(posedge clk)begin fan_zones2<=fan_zones;fan_boundary2<=fan_boundary;end
 wire target_region=page==2 && !m[189] && rendered_hand==m[48] && |(fan_zones2 & (12'b1<<m[52:49]));
 wire feedback_region=page==2 && m[203:202]!=0 && rendered_hand==m[204] && |(fan_zones2 & (12'b1<<m[208:205]));
 reg[23:0]rgb;
 always @*begin
  rgb=24'h0c1420;
  if(y2<56)rgb=24'h182a3e;
  if(perform && y2>=120 && y2<340)rgb=x2<320 ? 24'h102c38 : 24'h302238;
  if(perform && |fan_zones2)begin
   rgb=24'h1b3145;
   if(target_region)rgb=24'h8a6515;
   if(feedback_region)rgb=m[203:202]==1 ? 24'h25be70 : 24'hc43548;
   if(fan_boundary2)rgb=target_region ? 24'hffdf70 : 24'h78a5bc;
   if(sector_selected && fan_boundary2)rgb=24'h59ecf0;
  end
  if(perform && y2>=118 && y2<122 && ((x2<320)==!m[190]))rgb=24'h59ecf0;
  if(y2==56)rgb=24'h30516a;
  if(perform && volume_timer!=0 && y2>=105 && y2<111 && x2>=20 && x2<620)rgb=x2<20+((m[128:120]*10'd600)>>8) ? 24'h37ae9a : 24'h263b4c;
  if(page==1 && level<=2 && y2>=100+item*40 && y2<120+item*40)rgb=24'h28576a;
  if(page==1 && level>=3 && y2>=100+item*40 && y2<120+item*40)rgb=level==4 ? 24'h1a554b : 24'h28576a;
  if(col2<20 && bits[19-col2])rgb=x2<320 ? 24'h6de3d2 : 24'hf0b2dc;
 end
 always @(posedge clk)begin
  if(!rst_n)begin x<=0;y<=0;x1<=0;y1<=0;x2<=0;y2<=0;ui<=0;glyph<=0;bits<=0;col1<=0;row1<=0;col2<=0;red<=0;green<=0;blue<=0;de<=0;hsync<=1;vsync<=1;end
  else begin
   if(x==799)begin x<=0;y<=y==524 ? 0 : y+1'b1;end else x<=x+1'b1;
   if(status_update)ui<=status;
   glyph<=x<640 && y<480 ? (numeric ? (leading_blank ? 9'd0 : digit_glyph(digit)) : text_rom[address]) : 0;
   col1<=small_text ? small_col : x%20;row1<=small_text ? small_row : y%20;x1<=x;y1<=y;
   bits<=font_rom[glyph*20+row1];col2<=col1;x2<=x1;y2<=y1;
   {red,green,blue}<=rgb;de<=x2<640 && y2<480;
   hsync<=!(x2>=656 && x2<752);vsync<=!(y2>=490 && y2<492);
  end
 end
endmodule
