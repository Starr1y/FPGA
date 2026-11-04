// Warm 640x480 UI: character ROM, fan scan-line ROM, no framebuffer.
module reference_panel30(input clk,rst_n,input[1087:0]status,input status_update,
 output reg[7:0]red,green,blue,output reg hsync,vsync,de,output frame_request);
 reg[10:0]raster_x,raw_x1,raw_x2;reg[9:0]raster_y,raw_y1,raw_y2;
 wire[13:0]scaled_x={raster_x,2'b0}+raster_x;wire[11:0]scaled_y={raster_y,2'b0};
 wire[9:0]x=scaled_x>>3,y=scaled_y/12'd5;reg[9:0]x1,y1,x2,y2;reg[1087:0]ui;wire[31:0]course=ui[1087:1056];
 wire[255:0]m=ui[1055:800];wire[1:0]page=m[3:2];wire perform=page==0 || page==2;
 assign frame_request=raster_x==1311 && raster_y==599;
 reg[8:0]text_rom[0:8191] /* synthesis syn_romstyle="block_rom" */;
 reg[15:0]font_rom[0:4095] /* synthesis syn_romstyle="block_rom" */;
 reg[31:0]hand_rom[0:39] /* synthesis syn_romstyle="logic" */;
 reg[127:0]logo_rom[0:23] /* synthesis syn_romstyle="logic" */;
 initial begin $readmemh("rtl/ui23_text.hex",text_rom);$readmemh("rtl/ui23_font.hex",font_rom);$readmemh("rtl/ui23_hand.hex",hand_rom);$readmemh("rtl/ui23_logo.hex",logo_rom);end
 `include "rtl/ui23_labels.vh"
 wire[5:0]cell_x=x[9:4];wire[4:0]cell_y=y[8:4];wire hand=x>=320;
 wire[255:0]hs=hand ? ui[511:256] : ui[255:0];wire[5:0]hc=hand ? cell_x-6'd20 : cell_x;
 wire physical_link=hand ? m[12] : m[11];
 // Host-mode hand snapshots carry their own running/valid flags. Physical
 // diagnostics must still report the real IMU link, not simulated input.
 wire link=perform ? hs[0] : physical_link;
 wire[2:0]level=m[193:191],grp=m[196:194];wire[3:0]item=m[200:197];
 wire[1:0]label_profile=hand ? m[107:106] : m[105:104];
 wire[9:0]local_label_x=hand ? x-10'd336 : x-10'd24;
 reg[12:0]address;reg numeric;reg[15:0]number;reg[2:0]digit_position;
 reg small_text;reg[3:0]small_col,small_row;
 reg[8:0]text_glyph,override_glyph;reg use_text;
 wire[8:0]glyph=use_text ? text_glyph : override_glyph;
 reg[15:0]bits;reg[3:0]col1,row1,col2;
 reg[6:0]value_label,row_label;reg[5:0]row_field;reg[3:0]row_index;
 reg[2:0]side_row,list_row;reg side_valid,list_valid;
 reg[9:0]side_y,list_y;
 always @*begin
  side_row=0;side_valid=1;list_row=0;list_valid=1;
  case(cell_y)5'd7:side_row=0;5'd10:side_row=1;5'd13:side_row=2;5'd16:side_row=3;5'd19:side_row=4;5'd22:side_row=5;5'd25:side_row=6;default:side_valid=0;endcase
  case(cell_y)5'd9:list_row=0;5'd12:list_row=1;5'd15:list_row=2;5'd18:list_row=3;5'd21:list_row=4;5'd24:list_row=5;default:list_valid=0;endcase
  case(level==1 ? 4'd0 : level==2 ? item+4'd1 : {1'b0,grp}+4'd1)
   0:side_y=106;1:side_y=154;2:side_y=202;3:side_y=250;4:side_y=298;5:side_y=346;default:side_y=394;endcase
  case(grp==3 && item>=6 ? item-6 : item)0:list_y=140;1:list_y=188;2:list_y=236;3:list_y=284;4:list_y=332;default:list_y=380;endcase
 end
 function[12:0]label_address;input[6:0]id;input[5:0]col;
 // Express constant scaling without multiply inference. Gowin 1.9.12.03
 // raises SP00019 (10ATO32) for the multiply form in the complete design.
 begin label_address=col<20 ? 13'd4800+{id,4'b0}+{id,2'b0}+{7'b0,col} : 13'd0;end endfunction
 function[3:0]decimal_digit;input[15:0]n;input[2:0]pos;
 begin case(pos)0:decimal_digit=(n/10000)%10;1:decimal_digit=(n/1000)%10;2:decimal_digit=(n/100)%10;3:decimal_digit=(n/10)%10;default:decimal_digit=n%10;endcase end endfunction
 function[5:0]field_at;input[2:0]g;input[3:0]n;
 begin case(g)
 0:case(n)0:field_at=1;1:field_at=3;2:field_at=11;default:field_at=13;endcase
 1:case(n)0:field_at=2;1:field_at=4;2:field_at=12;default:field_at=14;endcase
 2:field_at=n==0 ? 9 : 10;
 3:case(n)0:field_at=7;1:field_at=31;2:field_at=32;3:field_at=15;4:field_at=16;5:field_at=17;default:field_at=18;endcase
 4:field_at=n==0 ? 19 : n==1 ? 23 : 27;
 default:case(n)0:field_at=0;1:field_at=8;2:field_at=21;default:field_at=28;endcase
 endcase end endfunction
 function[6:0]field_label;input[5:0]f;
 begin field_label=f>=29 ? L_GEST_LEFT+f-29 : f<20 ? L_FIELD0+f : f==23 ? L_INPUT_SOURCE : f==21 ? L_CENTER_BOTH : f==27 ? L_RESTART : L_RESET_HAND;end endfunction
 function[6:0]state_label;input[255:0]s;input connected;
 begin
  if(!connected)state_label=L_OFFLINE;else if(s[2])state_label=L_CENTERING;else if(!s[1])state_label=L_CENTER_WAIT;
  else if(s[5])state_label=L_RANGE;else if(s[6])state_label=L_DRIFT;else if(s[9:8]<2)state_label=L_QUALITY;
  else if(!s[7])state_label=L_STALE;else if(s[4])state_label=L_READY;else state_label=L_STALE;
 end endfunction
 function[6:0]note_label;input[1:0]p;input[3:0]z;
 begin
  case(p)
   1:case(z)0:note_label=L_DO;1:note_label=L_RE;2:note_label=L_MI;3:note_label=L_SOL;default:note_label=L_LA;endcase
   2:case(z)0:note_label=L_DO;1:note_label=L_DOS;2:note_label=L_RE;3:note_label=L_RES;4:note_label=L_MI;5:note_label=L_FA;6:note_label=L_FAS;7:note_label=L_SOL;8:note_label=L_SOLS;9:note_label=L_LA;10:note_label=L_LAS;default:note_label=L_SI;endcase
   default:case(z)0:note_label=L_DO;1:note_label=L_RE;2:note_label=L_MI;3:note_label=L_FA;4:note_label=L_SOL;5:note_label=L_LA;default:note_label=L_SI;endcase
  endcase
 end endfunction
 // Count changes, not zone changes, drive a 150ms strike pulse.
 reg[31:0]seen_hits[0:1];reg[24:0]hit_timer[0:1];
 reg[3:0]last_hit_zone[0:1];reg[1:0]last_hit_profile[0:1];integer h;
 always @(posedge clk)begin
  if(!rst_n)begin for(h=0;h<2;h=h+1)begin seen_hits[h]<=0;hit_timer[h]<=0;last_hit_zone[h]<=0;last_hit_profile[h]<=0;end end
  else for(h=0;h<2;h=h+1)begin
   if(hit_timer[h]!=0)hit_timer[h]<=hit_timer[h]-1'b1;
   if(!m[10] || !ui[h*256] || page!=0)hit_timer[h]<=0;
   if(status_update)begin
    seen_hits[h]<=status[h*256+128+:32];
    if(status[h*256+128+:32]!=seen_hits[h] && status[h*256+128+:32]!=0 && status[810] && status[h*256] && status[803:802]==0)begin
     hit_timer[h]<=25'd24500000;last_hit_zone[h]<=status[h*256+22+:4];last_hit_profile[h]<=status[h*256+26+:2];
    end
   end
  end
 end
 always @*begin
  address={page,10'b0}+{page,7'b0}+{page,5'b0}+{page,4'b0}+{cell_y,5'b0}+{cell_y,3'b0}+{7'b0,cell_x};
  numeric=0;number=0;digit_position=0;small_text=0;small_col=0;small_row=0;
  value_label=0;row_label=0;row_field=0;row_index=0;
  if(page==0)begin
   if(cell_y==2 && cell_x>=11 && cell_x<17)address=label_address(m[190] ? L_RIGHT : L_LEFT,cell_x-6'd11);
   if(cell_y==2 && cell_x>=22 && cell_x<29)address=label_address(m[10] ? L_PLAY : L_STOP,cell_x-6'd22);
   if(cell_y==2 && cell_x>=30 && cell_x<35)begin numeric=1;number=(m[128:120]*16'd100)>>8;digit_position=cell_x-6'd30;end
  end
  if(perform)begin
   if(cell_y==7 && hc>=2 && hc<10)address=label_address(hand ? L_RIGHT : L_LEFT,hc-6'd2);
   if(cell_y==8 && hc>=5 && hc<17)address=label_address(L_PIANO+(hand ? m[101:99] : m[98:96]),hc-6'd5);
   if(cell_y==21 && hc>=4 && hc<9)begin
    if(link && hs[4])begin numeric=1;number={12'b0,hs[21:18]}+1'b1;digit_position=hc-6'd4;end
    else address=label_address(L_DASH,hc-6'd4);
   end
   if(cell_y==21 && hc>=13 && hc<18)begin numeric=1;number={8'b0,hs[127:120]};digit_position=hc-6'd13;end
   if(cell_y==24 && hc>=2 && hc<18)address=label_address(state_label(hs,link),hc-6'd2);
   if(page==0 && hit_timer[hand]!=0 && cell_y==24)begin
    if(hc>=2 && hc<6)address=label_address(L_HIT,hc-6'd2);
    if(hc>=6 && hc<18)address=label_address(note_label(last_hit_profile[hand],last_hit_zone[hand]),hc-6'd6);
   end
   if(page==2)begin
    if(cell_y==1 && cell_x>=11 && cell_x<21)address=label_address(m[48] ? L_TARGET_RIGHT : L_TARGET_LEFT,cell_x-6'd11);
    if(cell_y==1 && cell_x>=26 && cell_x<31)begin numeric=1;number=course[0] ? (m[189] ? {4'b0,course[31:20]} : {4'b0,course[19:8]}+1'b1) : (m[189] ? 16 : {8'b0,m[47:40]}+1'b1);digit_position=cell_x-6'd26;end
    if(cell_y==1 && cell_x>=32 && cell_x<37)begin numeric=1;number=course[0] ? {4'b0,course[31:20]} : 16;digit_position=cell_x-6'd32;end
    if(cell_y==3 && cell_x>=26 && cell_x<31)begin numeric=1;number=m[79:64];digit_position=cell_x-6'd26;end
    if(cell_y==3 && cell_x>=34 && cell_x<39)begin numeric=1;number=m[95:80];digit_position=cell_x-6'd34;end
    if(m[189] && cell_y==24 && hc>=2 && hc<18)address=label_address(L_DONE,hc-6'd2);
   end
  end
  if(perform && cell_y==25)begin
   if(hc>=2 && hc<6)address=label_address(L_ANGLE,hc-6'd2);
   if(hc==8 && $signed(hs[63:48])<0)address=label_address(L_DASH,0);
   if(hc>=10 && hc<15)begin numeric=1;number=($signed(hs[63:48])<0 ? -$signed(hs[63:48]) : $signed(hs[63:48]))>>4;digit_position=hc-6'd10;end
  end
  if(perform && cell_y==20)begin
   if(hc>=2 && hc<6)address=label_address(L_LAST_NOTE,hc-6'd2);
   if(hc>=7 && hc<18)address=label_address(L_C4+m[246+hand*2+:2],hc-6'd7);
  end
  if(perform && cell_y==22)begin
   if(hc>=2 && hc<5)address=label_address(L_S1_KEY,hc-6'd2);
   if(hc==6)begin numeric=1;number=m[242+hand*2];digit_position=4;end
   if(hc>=11 && hc<14)address=label_address(L_S2_KEY,hc-6'd11);
   if(hc==15)begin numeric=1;number=m[243+hand*2];digit_position=4;end
  end
  if(perform && cell_y==23)begin
   if(hc>=2 && hc<10)address=label_address(L_C4+m[238+hand*2+:2],hc-6'd2);
   if(hc>=11 && hc<19)address=label_address(m[236+hand] ? L_GEST_HELD : L_GEST_IDLE,hc-6'd11);
  end
  if(page==1)begin
   if(side_valid && cell_x>=1 && cell_x<10)begin
    row_index={1'b0,side_row};address=label_address(row_index==0 ? L_QUICK : L_LEFT_GROUP+{3'b0,row_index}-7'd1,cell_x-6'd1);
   end
   if(cell_y==6 && cell_x>=13 && cell_x<38)address=label_address(level==1 ? L_QUICK : level==2 ? L_ALL : L_LEFT_GROUP+grp,cell_x-6'd13);
   if(list_valid && cell_x>=13 && cell_x<38)begin
    row_index={1'b0,list_row};if(grp==3 && level>=3 && item>=6)row_index=row_index+6;
    if(level==1 && row_index<5)begin
     case(row_index)0:row_label=L_START;1:row_label=L_MODE_SWITCH;2:row_label=L_CURRENT;3:row_label=L_ALL;default:row_label=L_DIAG;endcase
     address=label_address(row_label,cell_x-6'd13);
    end else if(level==2 && row_index<6)address=label_address(L_LEFT_GROUP+row_index,cell_x-6'd13);
    else if(level>=3 && row_index<(grp==3 ? 7 : grp==0 || grp==1 ? 4 : grp==4 ? 3 : grp==2 ? 2 : 4))begin
     row_field=field_at(grp,row_index);address=label_address(field_label(row_field),cell_x-6'd13);
    end else address=0;
   end
   if(level>=3)begin
    case({m[235],m[8:4]})
     0:value_label=L_OFFLINE_MODE+m[31:16];1,2:value_label=L_PIANO+m[31:16];
     3,4:value_label=L_SEVEN+m[31:16];5,6:value_label=L_C4+m[31:16];
     7,15,16,17,18,29,30,31,32:value_label=m[16] ? L_ON : L_OFF;
     9:value_label=L_NO_FX+m[31:16];13,14:value_label=L_RELEASE0+m[31:16];
     19:value_label=L_SONG_LEFT+m[31:16];23:value_label=m[16] ? L_PC_SOURCE : L_IMU_SOURCE;default:value_label=0;
    endcase
    if(cell_y==24 && cell_x>=13 && cell_x<18)begin numeric=1;number=m[31:16];digit_position=cell_x-6'd13;end
    if(cell_y==24 && cell_x>=21 && cell_x<38 && value_label!=0)address=label_address(value_label,cell_x-6'd21);
    if(cell_y==26 && cell_x>=13 && cell_x<38)address=label_address(level==5 ? L_CONFIRM : level==4 ? L_EDIT : L_SELECT,cell_x-6'd13);
   end
   if(level==1 && cell_x>=31 && cell_x<38)begin
    if(cell_y==9)address=label_address(m[10] ? L_PLAY : L_STOP,cell_x-6'd31);
    if(cell_y==12)address=label_address(L_OFFLINE_MODE+m[1:0],cell_x-6'd31);
    if(cell_y==15)address=label_address(m[190] ? L_RIGHT : L_LEFT,cell_x-6'd31);
   end
  end
  if(page==3)begin
   if(cell_y==2 && cell_x>=22 && cell_x<29)address=label_address(m[190] ? L_RIGHT : L_LEFT,cell_x-6'd22);
   if(cell_y==7 && hc>=6 && hc<17)address=label_address(hand ? L_RIGHT : L_LEFT,hc-6'd6);
   if(cell_y==10 && hc>=2 && hc<18)address=label_address(link ? L_ONLINE : L_LINK_OFF,hc-6'd2);
   if(cell_y==14 && hc>=2 && hc<18)address=label_address(!physical_link ? L_DASH : hs[2] ? L_CENTERING : hs[1] ? L_CENTER_DONE : L_CENTER_NONE,hc-6'd2);
   if(cell_y==19 && hc>=2 && hc<18)address=label_address(state_label(hs,link),hc-6'd2);
  end
  `include "rtl/ui23_note_labels.vh"
 end
 wire[3:0]digit=decimal_digit(number,digit_position);
 wire leading_blank=numeric && (digit_position==0 && number<10000 || digit_position==1 && number<1000 || digit_position==2 && number<100 || digit_position==3 && number<10);
 wire[9:0]fan_base=hand ? 336 : 24;wire[8:0]fan_col=x-fan_base,fan_row=y-10'd184;
 wire[11:0]fan_zones;wire fan_boundary;reg[11:0]fan_zones2;reg fan_boundary2;
 duo_fan fans(.clk(clk),.rst_n(rst_n),.profile(label_profile),.col(fan_col),.row(fan_row),
  .enabled(perform && x>=fan_base && x<fan_base+10'd280 && y>=184 && y<324),.zones(fan_zones),.boundary(fan_boundary));
 wire rh=x2>=320;wire[255:0]rs=rh ? ui[511:256] : ui[255:0];
 wire connected=perform ? rs[0] : (rh ? m[12] : m[11]);
 wire selected=rs[1] && |(fan_zones2 & (12'b1<<rs[21:18]));
 wire target_region=page==2 && !m[189] && rh==m[48] && |(fan_zones2 & (12'b1<<m[52:49]));
 wire feedback_region=page==2 && m[203:202]!=0 && rh==m[204] && |(fan_zones2 & (12'b1<<m[208:205]));
 wire struck=page==0 && hit_timer[rh]!=0 && last_hit_profile[rh]==(rh ? m[107:106] : m[105:104]) && |(fan_zones2 & (12'b1<<last_hit_zone[rh]));
 function rounded;input[9:0]px,py,left,top,width,height;reg[9:0]xx,yy;reg[3:0]inset;
 begin
  rounded=0;xx=px-left;yy=py-top;inset=0;
  if(yy==0 || yy==height-10'd1)inset=6;else if(yy==1 || yy==height-10'd2)inset=4;
  else if(yy==2 || yy==height-10'd3)inset=3;else if(yy==3 || yy==height-10'd4)inset=2;else if(yy<6 || yy>=height-10'd6)inset=1;
  if(px>=left && px<left+width && py>=top && py<top+height && xx>=inset && xx<width-{6'b0,inset})rounded=1;
 end endfunction
 reg[31:0]hand_bits1,hand_bits2;reg[4:0]hand_col1,hand_col2;reg hand_on1,hand_on2;
 reg[127:0]logo_bits1,logo_bits2;reg[6:0]logo_col1,logo_col2;reg logo_on1,logo_on2;
 wire[9:0]hand_row_delta=y-10'd264,logo_row_delta=y-10'd16;
 wire[5:0]hand_row_address=y>=264 && y<304 ? hand_row_delta[5:0] : 6'd0;
 wire[4:0]logo_row_address=y>=16 && y<40 ? logo_row_delta[4:0] : 5'd0;
 wire[9:0]hand_base=hand ? 460 : 148;
 always @(posedge clk)begin
  fan_zones2<=fan_zones;fan_boundary2<=fan_boundary;
  hand_bits1<=hand_rom[hand_row_address];hand_bits2<=hand_bits1;
  hand_col1<=x-hand_base;hand_col2<=hand_col1;
  hand_on1<=perform && x>=hand_base && x<hand_base+10'd32 && y>=264 && y<304;hand_on2<=hand_on1;
  logo_bits1<=logo_rom[logo_row_address];logo_bits2<=logo_bits1;
  logo_col1<=x-16;logo_col2<=logo_col1;logo_on1<=x>=16 && x<144 && y>=16 && y<40;logo_on2<=logo_on1;
 end
 reg[23:0]rgb,ink;wire[16:0]volume_product={8'b0,m[128:120]}*17'd112;
 wire[8:0]volume_width=volume_product[16:8];
 always @*begin
  rgb=24'hf3dfb5;ink=24'h242532;
  if(rounded(x2,y2,10'd8,10'd8,10'd624,10'd72))rgb=24'hfffdf7;
  if(rounded(x2,y2,10'd8,10'd424,10'd624,10'd48))rgb=24'hfffdf7;
  if(page!=1)begin
   if(rounded(x2,y2,10'd12,10'd100,10'd302,10'd316) || rounded(x2,y2,10'd326,10'd100,10'd302,10'd316))rgb=24'he8cea2;
   if(rounded(x2,y2,10'd12,10'd96,10'd302,10'd316) || rounded(x2,y2,10'd326,10'd96,10'd302,10'd316))rgb=24'hfffdf7;
  end else begin
   if(rounded(x2,y2,10'd8,10'd88,10'd168,10'd328))rgb=24'hfaf1df;
   if(rounded(x2,y2,10'd184,10'd88,10'd448,10'd328))rgb=24'hfffdf7;
   if(rounded(x2,y2,10'd12,side_y,10'd160,10'd32))rgb=24'hffdec1;
   if(level<=4 && rounded(x2,y2,10'd196,list_y,10'd424,10'd32))rgb=level==4 ? 24'hffcfb4 : 24'hf8ead8;
   if(level>=3 && rounded(x2,y2,10'd196,10'd380,10'd424,10'd32))rgb=24'hf6e5cb;
  end
  if(perform)begin
   if(|fan_zones2)begin
    rgb=!connected ? 24'he6e2d9 : rh ? 24'hffdda3 : 24'hffc3aa;
    if(selected)rgb=connected && rs[4] ? (rh ? 24'hffb447 : 24'hff7956) : 24'hb5ada0;
    if(target_region)rgb=24'hf6c04b;
    if(struck)rgb=rh ? 24'hf09324 : 24'hf24b32;
    if(feedback_region)rgb=m[203:202]==1 ? 24'h20b57a : 24'he94444;
    if(fan_boundary2)rgb=24'hfffdf7;
    if((selected || target_region || struck || feedback_region) && fan_boundary2)rgb=rh ? 24'hd98221 : 24'he94e36;
   end
   if(y2>=104 && y2<107 && ((x2>=32 && x2<120 && !m[190]) || (x2>=344 && x2<432 && m[190])))rgb=rh ? 24'hf19b32 : 24'hf25538;
   if(rounded(x2,y2,rh ? 10'd344 : 10'd32,10'd328,10'd128,10'd32) || rounded(x2,y2,rh ? 10'd488 : 10'd176,10'd328,10'd124,10'd32))rgb=rh ? 24'hffebc9 : 24'hffe2d4;
   if(hand_on2 && hand_bits2[~hand_col2])rgb=!connected ? 24'hb9b6af : rh ? 24'hee9b33 : 24'hf25538;
  end
  if(page==0 && y2>=62 && y2<67 && x2>=496 && x2<608)rgb=x2<10'd496+{1'b0,volume_width} ? 24'hf25538 : 24'hf6dfbf;
  if(page==3)begin
   if(rounded(x2,y2,rh ? 10'd344 : 10'd32,10'd152,10'd176,10'd32))rgb=connected ? 24'he0f3e8 : 24'hffe4df;
   if(rounded(x2,y2,rh ? 10'd344 : 10'd32,10'd216,10'd240,10'd32))rgb=24'hf8efdf;
   if(rounded(x2,y2,rh ? 10'd344 : 10'd32,10'd296,10'd240,10'd32))rgb=24'hf8efdf;
  end
  if(perform && y2>=112 && y2<128)ink=rh ? 24'hb46a16 : 24'hd9452e;
  if(perform && |fan_zones2 && (struck || feedback_region))ink=24'hffffff;
  if(page==1 && y2>=416 && y2<432)ink=24'hbd4b2e;
  if(page==3 && y2>=160 && y2<176)ink=connected ? 24'h008757 : 24'hd33737;
  if(y2>=432)ink=24'h56525a;
  if(col2<16 && bits[15-col2])rgb=ink;
  if(logo_on2 && logo_bits2[~logo_col2])rgb=24'h242532;
 end
 // Keep inferred synchronous ROM reads in independent clocked blocks. The
 // glyph override mux is after the text ROM Q, so no ROM reset/mux inference
 // depends on constants propagated from the surrounding instrument design.
 always @(posedge clk)text_glyph<=text_rom[address];
 always @(posedge clk)bits<=font_rom[{glyph[7:0],row1}];
 always @(posedge clk)begin
  if(!rst_n)begin raster_x<=0;raster_y<=0;raw_x1<=0;raw_x2<=0;raw_y1<=0;raw_y2<=0;x1<=0;y1<=0;x2<=0;y2<=0;ui<=0;use_text<=0;override_glyph<=0;col1<=0;row1<=0;col2<=0;red<=0;green<=0;blue<=0;de<=0;hsync<=1;vsync<=1;end
  else begin
   if(raster_x==1311)begin raster_x<=0;raster_y<=raster_y==623 ? 0 : raster_y+1'b1;end else raster_x<=raster_x+1'b1;
   raw_x1<=raster_x;raw_x2<=raw_x1;raw_y1<=raster_y;raw_y2<=raw_y1;
   if(status_update)ui<=status;
   use_text<=x<640 && y<480 && !numeric && !(page==0 && cell_y==2 && cell_x==35);
   override_glyph<=x<640 && y<480 ? (page==0 && cell_y==2 && cell_x==35 ? GLYPH_PERCENT : numeric ? (leading_blank ? 9'd0 : digit_glyph(digit)) : 0) : 0;
   col1<=small_text ? small_col : x[3:0];row1<=small_text ? small_row : y[3:0];x1<=x;y1<=y;
   col2<=col1;x2<=x1;y2<=y1;
   {red,green,blue}<=rgb;de<=raw_x2<1024 && raw_y2<600;
   hsync<=!(raw_x2>=1072 && raw_x2<1168);vsync<=!(raw_y2>=603 && raw_y2<613);
  end
 end
endmodule
