// Procedural bench UI: no framebuffer; status is measured, not a screenshot.
module video_instrument_panel #(parameter SAFE_LAYOUT=1)(
 input clk,input rst_n,input [39:0] levels,input signed [7:0] mix_sample,
 input sample_update,input [1023:0] performance_status,input status_update,
 output reg [7:0] red,green,blue,output hsync,vsync,de,output frame_request);
 reg [9:0] x=0,y=0;
 always @(posedge clk)if(!rst_n)begin x<=0;y<=0;end
 else if(x==799)begin x<=0;y<=y==524 ? 0 : y+1'b1;end else x<=x+1'b1;
 wire raster_de=x<640 && y<480;
 wire raster_hsync=!(x>=656 && x<752),raster_vsync=!(y>=490 && y<492);
 reg de_p,hsync_p,vsync_p;
 assign de=de_p;assign hsync=hsync_p;assign vsync=vsync_p;
 assign frame_request=x==799 && y==479;
    reg [1023:0] ui_status;
    wire spi_mode=ui_status[965];
    reg [15:0] bcd[0:15];
    reg [1:0] format_state;
    reg [4:0] number_index;reg [3:0] shift_count;
    reg [31:0] shift_word;
    reg [31:0] adjusted;
    integer n;
    function [15:0] angle_magnitude;
        input signed [15:0] angle;
        reg [15:0] mag;
        begin mag=angle<0 ? -angle : angle;angle_magnitude=(mag+8)>>4;end
    endfunction
    function [15:0] number_value;
        input [4:0] id;
        begin case(id)
            0:number_value=angle_magnitude(ui_status[31:16]);
            1:number_value=angle_magnitude(ui_status[47:32]);
            2:number_value=angle_magnitude(ui_status[63:48]);
            3:number_value=ui_status[127:112]>999 ? 999 : ui_status[127:112];
            4:number_value=ui_status[143:128]>999 ? 999 : ui_status[143:128];
            5:number_value=ui_status[159:144]>999 ? 999 : ui_status[159:144];
            6:number_value=ui_status[191:160]>9999 ? 9999 : ui_status[175:160];
            7:number_value=ui_status[223:192]>9999 ? 9999 : ui_status[207:192];
            8:number_value=$signed(ui_status[79:64])<0 ? -$signed(ui_status[79:64]) : ui_status[79:64];
            9:number_value=$signed(ui_status[95:80])<0 ? -$signed(ui_status[95:80]) : ui_status[95:80];
            10:number_value={8'b0,ui_status[103:96]};
            11:number_value={8'b0,ui_status[111:104]};
            12:number_value=ui_status[232:227]*2;
            13:number_value=ui_status[929:914]>9999 ? 9999 : ui_status[929:914];
            14:number_value=ui_status[945:930]>9999 ? 9999 : ui_status[945:930];
            15:number_value=ui_status[961:946]>9999 ? 9999 : ui_status[961:946];
            default:number_value=0;
        endcase end
    endfunction
    always @* begin
        adjusted=shift_word;
        for(n=4;n<8;n=n+1) if(adjusted[n*4+:4]>=5) adjusted[n*4+:4]=adjusted[n*4+:4]+3;
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            ui_status<=0;ui_status[242:240]<=3;ui_status[103:96]<=128;
            format_state<=0;number_index<=0;shift_count<=0;shift_word<=0;
            for(n=0;n<16;n=n+1) bcd[n]<=0;
        end else begin
            case(format_state)
                1:begin shift_word<={16'b0,number_value(number_index)};shift_count<=0;format_state<=2;end
                2:begin
                    shift_word<=adjusted<<1;
                    if(shift_count==15) begin
                        bcd[number_index]<=adjusted[30:15];
                        if(number_index==15) format_state<=0;
                        else begin number_index<=number_index+1'b1;format_state<=1;end
                    end else shift_count<=shift_count+1'b1;
                end
            endcase
            // In the actual HDMI wrapper this pulse arrives in vertical blank.
            if(status_update) begin ui_status<=performance_status;number_index<=0;format_state<=1;end
        end
    end
    function [7:0] digit;
        input [4:0] id;input [2:0] pos;
        begin digit=pos<4 ? "0"+((bcd[id]>>(12-pos*4))&15) : " ";end
    endfunction
    function [7:0] char_at;
        input [255:0] text;input [5:0] length,pos;
        begin char_at=pos<length ? text[(length-pos-1)*8+:8] : " ";end
    endfunction

 wire [1:0] layout_profile=ui_status[1014:1013];
 wire [3:0] note_count=layout_profile==1 ? 5 : layout_profile==2 ? 12 : 7;
 wire [3:0] selected_note=ui_status[1008:1005],last_note=ui_status[1012:1009];
 wire [11:0] hit_notes=ui_status[331:320];
 wire selected_visible=!ui_status[6] || (ui_status[7] && !ui_status[8] && ui_status[5:4]>=2 && !ui_status[10] && !ui_status[11] && ui_status[14]);
 function [31:0] note_text;input [1:0] p;input [3:0] note;
 begin case(p)
 0:case(note)
 0:note_text="DO  ";
 1:note_text="RE  ";
 2:note_text="MI  ";
 3:note_text="FA  ";
 4:note_text="SOL ";
 5:note_text="LA  ";
 6:note_text="SI  ";
 default:note_text="----";endcase
 1:case(note)
 0:note_text="DO  ";
 1:note_text="RE  ";
 2:note_text="MI  ";
 3:note_text="SOL ";
 4:note_text="LA  ";
 default:note_text="----";endcase
 2:case(note)
 0:note_text="DO  ";
 1:note_text="DO# ";
 2:note_text="RE  ";
 3:note_text="RE# ";
 4:note_text="MI  ";
 5:note_text="FA  ";
 6:note_text="FA# ";
 7:note_text="SOL ";
 8:note_text="SOL#";
 9:note_text="LA  ";
 10:note_text="LA# ";
 11:note_text="SI  ";
 default:note_text="----";endcase
 default:note_text="----";endcase end endfunction
 function [31:0] four;input [4:0] id;begin four={digit(id,0),digit(id,1),digit(id,2),digit(id,3)};end endfunction
 function [7:0] hexchar;input [3:0] value;begin hexchar=value<10 ? 8'd48+value : 8'd65+value-10;end endfunction
 function [23:0] three;input [4:0] id;begin three={digit(id,1),digit(id,2),digit(id,3)};end endfunction
 function [39:0] angle_text;input [4:0] id;input signed [15:0] value;
 begin angle_text=ui_status[6] ? {value<0 ? 8'd45 : 8'd43,three(id),8'd68} : "---- ";end endfunction
 wire manual_on=ui_status[969];
 reg [3:0] zone_index;reg [9:0] zone_x;wire [9:0] zone_width=layout_profile==1 ? 108 : layout_profile==2 ? 42 : 76;
 wire diagnostic_view=ui_status[1003];
 always @* begin zone_index=0;zone_x=32;
 case(layout_profile)
 0:begin
 if(x>=32)begin zone_index=0;zone_x=32;end
 if(x>=114)begin zone_index=1;zone_x=114;end
 if(x>=196)begin zone_index=2;zone_x=196;end
 if(x>=278)begin zone_index=3;zone_x=278;end
 if(x>=360)begin zone_index=4;zone_x=360;end
 if(x>=442)begin zone_index=5;zone_x=442;end
 if(x>=524)begin zone_index=6;zone_x=524;end
 end
 1:begin
 if(x>=32)begin zone_index=0;zone_x=32;end
 if(x>=146)begin zone_index=1;zone_x=146;end
 if(x>=260)begin zone_index=2;zone_x=260;end
 if(x>=374)begin zone_index=3;zone_x=374;end
 if(x>=488)begin zone_index=4;zone_x=488;end
 end
 2:begin
 if(x>=32)begin zone_index=0;zone_x=32;end
 if(x>=80)begin zone_index=1;zone_x=80;end
 if(x>=128)begin zone_index=2;zone_x=128;end
 if(x>=176)begin zone_index=3;zone_x=176;end
 if(x>=224)begin zone_index=4;zone_x=224;end
 if(x>=272)begin zone_index=5;zone_x=272;end
 if(x>=320)begin zone_index=6;zone_x=320;end
 if(x>=368)begin zone_index=7;zone_x=368;end
 if(x>=416)begin zone_index=8;zone_x=416;end
 if(x>=464)begin zone_index=9;zone_x=464;end
 if(x>=512)begin zone_index=10;zone_x=512;end
 if(x>=560)begin zone_index=11;zone_x=560;end
 end
 default:begin zone_index=0;zone_x=32;end endcase end
 wire key_box=diagnostic_view && x>=32 && x-zone_x<zone_width && y>=326 && y<390;
 wire selected=selected_visible && zone_index==selected_note;
 wire hit=hit_notes[zone_index];
 wire key_edge=key_box && (x-zone_x<2 || x-zone_x>=zone_width-2 || y<328 || y>=388);
 wire [11:0] fan_zones;wire fan_edge;
 video_fan_map fan(.clk(clk),.rst_n(rst_n),.profile(layout_profile),.x(x),.y(y),.enabled(!diagnostic_view),.zones(fan_zones),.boundary(fan_edge));
 // Performance page keeps actionable status visible; numeric diagnostics live on the second page.
 wire [5:0] pose_label=ui_status[3:0]==9 ? 37 : ui_status[3:0]==10 ? 36 : ui_status[3:0]==1 ? 8 : ui_status[3:0]==2 ? 9 : ui_status[3:0]==3 ? 10 : ui_status[3:0]==4 ? 11 : ui_status[3:0]==5 ? 12 : ui_status[3:0]==6 ? 13 : ui_status[3:0]==7 ? 14 : ui_status[3:0]==8 ? 15 : 7;
 wire [5:0] link_label=!manual_on ? 3 : ui_status[249:247]==5 ? 20 : ui_status[249:247]==3 ? 18 : ui_status[249:247]==2 ? 17 : ui_status[249:247]==4 ? 19 : 16;
 wire [5:0] main_label=!manual_on || !ui_status[6] ? link_label : pose_label;
 wire [5:0] help_label=!manual_on ? 31 : ui_status[249:247]==5 ? 44 : !ui_status[6] ? 19 : ui_status[3:0]==3 ? 35 : (ui_status[3:0]==1 || ui_status[3:0]==10) ? 36 : (ui_status[3:0]==2 || ui_status[3:0]==4 || ui_status[3:0]==5 || ui_status[3:0]==9) ? 43 : 42;
 reg zh;reg [9:0] text_x,text_y;reg [5:0] text_len,label_id;
 reg [255:0] text;reg font_double;reg [1:0] ink;
 always @* begin
 zh=0;text_x=0;text_y=0;text_len=0;label_id=0;text=0;font_double=0;ink=1;
if(x>=32 && x<32+7*16 && y>=24 && y<24+24)begin zh=0;text_x=32;text_y=24;text_len=7;text="TANGLAB";font_double=1;ink=1;end
if(x>=184 && x<184+4*24 && y>=24 && y<24+24)begin zh=1;text_x=184;text_y=24;text_len=4;label_id=0;ink=2;end
if(x>=552 && x<552+2*24 && y>=24 && y<24+24)begin zh=1;text_x=552;text_y=24;text_len=2;label_id=diagnostic_view ? 40 : 39;ink=1;end
if(x>=32 && x<32+6*8 && y>=68 && y<68+12)begin zh=0;text_x=32;text_y=68;text_len=6;text="KEY1+2";font_double=0;ink=1;end
if(x>=90 && x<90+4*24 && y>=60 && y<60+24)begin zh=1;text_x=90;text_y=60;text_len=4;label_id=ui_status[1004] ? 47 : 31;ink=ui_status[1004] ? 2 : 1;end
if(diagnostic_view)begin if(x>=224 && x<224+17*8 && y>=68 && y<68+12)begin zh=0;text_x=224;text_y=68;text_len=17;text="I2C250K / FAN04  ";font_double=0;ink=1;end end
if(!diagnostic_view)begin if(x>=248 && x<248+5*8 && y>=68 && y<68+12)begin zh=0;text_x=248;text_y=68;text_len=5;text="FAN04";font_double=0;ink=1;end end
if(x>=520 && x<520+3*24 && y>=60 && y<60+24)begin zh=1;text_x=520;text_y=60;text_len=3;label_id=manual_on ? 4 : 3;ink=1;end
 if(!diagnostic_view)begin
if(x>=48 && x<48+4*24 && y>=104 && y<104+24)begin zh=1;text_x=48;text_y=104;text_len=4;label_id=main_label;ink=(!manual_on || ui_status[249:247]==5 || (ui_status[6] && ui_status[3:0]!=7 && ui_status[3:0]!=8)) ? 2 : 1;end
if(x>=244 && x<244+4*24 && y>=104 && y<104+24)begin zh=1;text_x=244;text_y=104;text_len=4;label_id=help_label;ink=1;end
if(x>=552 && x<552+2*24 && y>=104 && y<104+24)begin zh=1;text_x=552;text_y=104;text_len=2;label_id=34;ink=2;end
if(x>=32 && x<32+2*24 && y>=164 && y<164+24)begin zh=1;text_x=32;text_y=164;text_len=2;label_id=25;ink=1;end
if(x>=88 && x<88+4*16 && y>=164 && y<164+24)begin zh=0;text_x=88;text_y=164;text_len=4;text=selected_visible ? note_text(layout_profile,selected_note) : "----";font_double=1;ink=1;end
if(x>=230 && x<230+2*24 && y>=164 && y<164+24)begin zh=1;text_x=230;text_y=164;text_len=2;label_id=26;ink=2;end
if(x>=286 && x<286+4*16 && y>=164 && y<164+24)begin zh=0;text_x=286;text_y=164;text_len=4;text=ui_status[15] ? note_text(ui_status[1016:1015],last_note) : "----";font_double=1;ink=2;end
if(x>=448 && x<448+2*24 && y>=164 && y<164+24)begin zh=1;text_x=448;text_y=164;text_len=2;label_id=27;ink=2;end
if(x>=512 && x<512+4*8 && y>=172 && y<172+12)begin zh=0;text_x=512;text_y=172;text_len=4;text=four(7);font_double=0;ink=2;end
if(x>=32 && x<32+4*24 && y>=208 && y<208+24)begin zh=1;text_x=32;text_y=208;text_len=4;label_id=48+layout_profile;ink=1;end
if(x>=464 && x<464+4*24 && y>=208 && y<208+24)begin zh=1;text_x=464;text_y=208;text_len=4;label_id=51;ink=1;end
if(x>=32 && x<32+4*8 && y>=254 && y<254+12)begin zh=0;text_x=32;text_y=254;text_len=4;text="KEY0";font_double=0;ink=1;end
if(x>=32 && x<32+4*24 && y>=270 && y<270+24)begin zh=1;text_x=32;text_y=270;text_len=4;label_id=ui_status[1022] ? 54 : 53;ink=ui_status[1022] ? 2 : 1;end
if(x>=32 && x<32+2*24 && y>=340 && y<340+24)begin zh=1;text_x=32;text_y=340;text_len=2;label_id=28;ink=1;end
if(x>=88 && x<88+3*8 && y>=348 && y<348+12)begin zh=0;text_x=88;text_y=348;text_len=3;text=three(11);font_double=0;ink=2;end
if(x>=32 && x<32+4*24 && y>=392 && y<392+24)begin zh=1;text_x=32;text_y=392;text_len=4;label_id=45;ink=1;end
if(x>=512 && x<512+4*24 && y>=392 && y<392+24)begin zh=1;text_x=512;text_y=392;text_len=4;label_id=46;ink=2;end
if(x>=296 && x<296+2*24 && y>=380 && y<380+24)begin zh=1;text_x=296;text_y=380;text_len=2;label_id=52;ink=1;end
 if(layout_profile==0)begin
if(x>=139 && x<139+4*16 && y>=345 && y<345+24)begin zh=0;text_x=139;text_y=345;text_len=4;text=note_text(layout_profile,4'd0);font_double=1;ink=hit_notes[0] ? 2 : 1;end
if(x>=172 && x<172+4*16 && y>=278 && y<278+24)begin zh=0;text_x=172;text_y=278;text_len=4;text=note_text(layout_profile,4'd1);font_double=1;ink=hit_notes[1] ? 2 : 1;end
if(x>=231 && x<231+4*16 && y>=231 && y<231+24)begin zh=0;text_x=231;text_y=231;text_len=4;text=note_text(layout_profile,4'd2);font_double=1;ink=hit_notes[2] ? 2 : 1;end
if(x>=304 && x<304+4*16 && y>=214 && y<214+24)begin zh=0;text_x=304;text_y=214;text_len=4;text=note_text(layout_profile,4'd3);font_double=1;ink=hit_notes[3] ? 2 : 1;end
if(x>=369 && x<369+4*16 && y>=231 && y<231+24)begin zh=0;text_x=369;text_y=231;text_len=4;text=note_text(layout_profile,4'd4);font_double=1;ink=hit_notes[4] ? 2 : 1;end
if(x>=436 && x<436+4*16 && y>=278 && y<278+24)begin zh=0;text_x=436;text_y=278;text_len=4;text=note_text(layout_profile,4'd5);font_double=1;ink=hit_notes[5] ? 2 : 1;end
if(x>=469 && x<469+4*16 && y>=345 && y<345+24)begin zh=0;text_x=469;text_y=345;text_len=4;text=note_text(layout_profile,4'd6);font_double=1;ink=hit_notes[6] ? 2 : 1;end
 end
 if(layout_profile==1)begin
if(x>=143 && x<143+4*16 && y>=331 && y<331+24)begin zh=0;text_x=143;text_y=331;text_len=4;text=note_text(layout_profile,4'd0);font_double=1;ink=hit_notes[0] ? 2 : 1;end
if(x>=205 && x<205+4*16 && y>=246 && y<246+24)begin zh=0;text_x=205;text_y=246;text_len=4;text=note_text(layout_profile,4'd1);font_double=1;ink=hit_notes[1] ? 2 : 1;end
if(x>=304 && x<304+4*16 && y>=214 && y<214+24)begin zh=0;text_x=304;text_y=214;text_len=4;text=note_text(layout_profile,4'd2);font_double=1;ink=hit_notes[2] ? 2 : 1;end
if(x>=395 && x<395+4*16 && y>=246 && y<246+24)begin zh=0;text_x=395;text_y=246;text_len=4;text=note_text(layout_profile,4'd3);font_double=1;ink=hit_notes[3] ? 2 : 1;end
if(x>=465 && x<465+4*16 && y>=331 && y<331+24)begin zh=0;text_x=465;text_y=331;text_len=4;text=note_text(layout_profile,4'd4);font_double=1;ink=hit_notes[4] ? 2 : 1;end
 end
 if(layout_profile==2)begin
if(x>=144 && x<144+4*8 && y>=367 && y<367+12)begin zh=0;text_x=144;text_y=367;text_len=4;text=note_text(layout_profile,4'd0);font_double=0;ink=hit_notes[0] ? 2 : 1;end
if(x>=152 && x<152+4*8 && y>=324 && y<324+12)begin zh=0;text_x=152;text_y=324;text_len=4;text=note_text(layout_profile,4'd1);font_double=0;ink=hit_notes[1] ? 2 : 1;end
if(x>=178 && x<178+4*8 && y>=286 && y<286+12)begin zh=0;text_x=178;text_y=286;text_len=4;text=note_text(layout_profile,4'd2);font_double=0;ink=hit_notes[2] ? 2 : 1;end
if(x>=205 && x<205+4*8 && y>=255 && y<255+12)begin zh=0;text_x=205;text_y=255;text_len=4;text=note_text(layout_profile,4'd3);font_double=0;ink=hit_notes[3] ? 2 : 1;end
if(x>=247 && x<247+4*8 && y>=233 && y<233+12)begin zh=0;text_x=247;text_y=233;text_len=4;text=note_text(layout_profile,4'd4);font_double=0;ink=hit_notes[4] ? 2 : 1;end
if(x>=290 && x<290+4*8 && y>=221 && y<221+12)begin zh=0;text_x=290;text_y=221;text_len=4;text=note_text(layout_profile,4'd5);font_double=0;ink=hit_notes[5] ? 2 : 1;end
if(x>=330 && x<330+4*8 && y>=221 && y<221+12)begin zh=0;text_x=330;text_y=221;text_len=4;text=note_text(layout_profile,4'd6);font_double=0;ink=hit_notes[6] ? 2 : 1;end
if(x>=373 && x<373+4*8 && y>=233 && y<233+12)begin zh=0;text_x=373;text_y=233;text_len=4;text=note_text(layout_profile,4'd7);font_double=0;ink=hit_notes[7] ? 2 : 1;end
if(x>=407 && x<407+4*8 && y>=255 && y<255+12)begin zh=0;text_x=407;text_y=255;text_len=4;text=note_text(layout_profile,4'd8);font_double=0;ink=hit_notes[8] ? 2 : 1;end
if(x>=446 && x<446+4*8 && y>=286 && y<286+12)begin zh=0;text_x=446;text_y=286;text_len=4;text=note_text(layout_profile,4'd9);font_double=0;ink=hit_notes[9] ? 2 : 1;end
if(x>=464 && x<464+4*8 && y>=324 && y<324+12)begin zh=0;text_x=464;text_y=324;text_len=4;text=note_text(layout_profile,4'd10);font_double=0;ink=hit_notes[10] ? 2 : 1;end
if(x>=480 && x<480+4*8 && y>=367 && y<367+12)begin zh=0;text_x=480;text_y=367;text_len=4;text=note_text(layout_profile,4'd11);font_double=0;ink=hit_notes[11] ? 2 : 1;end
 end
 end else begin
if(x>=48 && x<48+2*24 && y>=104 && y<104+24)begin zh=1;text_x=48;text_y=104;text_len=2;label_id=5;ink=1;end
if(x>=170 && x<170+4*24 && y>=104 && y<104+24)begin zh=1;text_x=170;text_y=104;text_len=4;label_id=38;ink=1;end
if(x>=382 && x<382+2*24 && y>=104 && y<104+24)begin zh=1;text_x=382;text_y=104;text_len=2;label_id=6;ink=2;end
if(x>=48 && x<48+4*24 && y>=140 && y<140+24)begin zh=1;text_x=48;text_y=140;text_len=4;label_id=pose_label;ink=1;end
if(ui_status[6] && (ui_status[3:0]==1 || ui_status[3:0]==3 || ui_status[3:0]==9))begin if(x>=170 && x<170+4*24 && y>=140 && y<140+24)begin zh=1;text_x=170;text_y=140;text_len=4;label_id=ui_status[5:4]<2 ? 35 : 36;ink=2;end end
if(x>=382 && x<382+4*24 && y>=140 && y<140+24)begin zh=1;text_x=382;text_y=140;text_len=4;label_id=link_label;ink=1;end
if(ui_status[249:247]==5)begin if(x>=496 && x<496+3*8 && y>=148 && y<148+12)begin zh=0;text_x=496;text_y=148;text_len=3;text={"F0",hexchar(ui_status[973:970])};font_double=0;ink=2;end end
if(x>=48 && x<48+2*24 && y>=178 && y<178+24)begin zh=1;text_x=48;text_y=178;text_len=2;label_id=21;ink=1;end
if(x>=100 && x<100+5*8 && y>=185 && y<185+12)begin zh=0;text_x=100;text_y=185;text_len=5;text=angle_text(0,ui_status[31:16]);font_double=0;ink=1;end
if(x>=204 && x<204+2*24 && y>=178 && y<178+24)begin zh=1;text_x=204;text_y=178;text_len=2;label_id=22;ink=1;end
if(x>=256 && x<256+5*8 && y>=185 && y<185+12)begin zh=0;text_x=256;text_y=185;text_len=5;text=angle_text(1,ui_status[47:32]);font_double=0;ink=1;end
if(x>=48 && x<48+2*24 && y>=214 && y<214+24)begin zh=1;text_x=48;text_y=214;text_len=2;label_id=23;ink=1;end
if(x>=100 && x<100+5*8 && y>=221 && y<221+12)begin zh=0;text_x=100;text_y=221;text_len=5;text=angle_text(2,ui_status[63:48]);font_double=0;ink=1;end
if(x>=204 && x<204+2*24 && y>=214 && y<214+24)begin zh=1;text_x=204;text_y=214;text_len=2;label_id=24;ink=1;end
if(x>=260 && x<260+3*8 && y>=221 && y<221+12)begin zh=0;text_x=260;text_y=221;text_len=3;text={"0"+{6'b0,ui_status[5:4]},"/3"};font_double=0;ink=1;end
if(x>=382 && x<382+17*8 && y>=178 && y<178+12)begin zh=0;text_x=382;text_y=178;text_len=17;text={"RX ",four(13),"  PKT ",four(14)};font_double=0;ink=1;end
if(x>=382 && x<382+17*8 && y>=198 && y<198+12)begin zh=0;text_x=382;text_y=198;text_len=17;text={"ERR ",four(6)," RST ",four(15)};font_double=0;ink=2;end
if(x>=382 && x<382+18*8 && y>=218 && y<218+12)begin zh=0;text_x=382;text_y=218;text_len=18;text={"CFG Q",8'd48+ui_status[250]," A",8'd48+ui_status[251]," G",8'd48+ui_status[252]," L",8'd48+ui_status[253]," V",8'd48+ui_status[254]};font_double=0;ink=1;end
if(x>=382 && x<382+17*8 && y>=238 && y<238+12)begin zh=0;text_x=382;text_y=238;text_len=17;text={"HZ P",three(3)," A",three(4)," G",three(5)};font_double=0;ink=1;end
if(ui_status[249:247]==5)begin if(x>=382 && x<382+17*8 && y>=238 && y<238+12)begin zh=0;text_x=382;text_y=238;text_len=17;text={"I",8'd48+ui_status[991]," S",8'd48+ui_status[990]," H",hexchar(ui_status[989:986]),hexchar(ui_status[985:982]),hexchar(ui_status[981:978]),hexchar(ui_status[977:974])," E0",hexchar(ui_status[995:992]),"  "};font_double=0;ink=1;end end
if(x>=550 && x<550+4*8 && y>=238 && y<238+12)begin zh=0;text_x=550;text_y=238;text_len=4;text={"ACK",8'd48+ui_status[996]};font_double=0;ink=1;end
if(x>=550 && x<566 && y>=260 && y<272)begin zh=0;text_x=550;text_y=260;text_len=2;text={"T",8'd48+{6'd0,ui_status[309:308]}};font_double=0;ink=1;end
if(x>=382 && x<382+13*8 && y>=260 && y<260+12)begin zh=0;text_x=382;text_y=260;text_len=13;text={"QUAL Q",8'd48+ui_status[5:4]," A",8'd48+ui_status[1000:999]," G",8'd48+ui_status[1002:1001]};font_double=0;ink=1;end
if(x>=32 && x<32+2*24 && y>=290 && y<290+24)begin zh=1;text_x=32;text_y=290;text_len=2;label_id=25;ink=1;end
if(x>=88 && x<88+4*16 && y>=290 && y<290+24)begin zh=0;text_x=88;text_y=290;text_len=4;text=selected_visible ? note_text(layout_profile,selected_note) : "----";font_double=1;ink=1;end
if(x>=230 && x<230+2*24 && y>=290 && y<290+24)begin zh=1;text_x=230;text_y=290;text_len=2;label_id=26;ink=2;end
if(x>=286 && x<286+4*16 && y>=290 && y<290+24)begin zh=0;text_x=286;text_y=290;text_len=4;text=ui_status[15] ? note_text(ui_status[1016:1015],last_note) : "----";font_double=1;ink=2;end
if(x>=448 && x<448+2*24 && y>=290 && y<290+24)begin zh=1;text_x=448;text_y=290;text_len=2;label_id=27;ink=2;end
if(x>=512 && x<512+4*8 && y>=298 && y<298+12)begin zh=0;text_x=512;text_y=298;text_len=4;text=four(7);font_double=0;ink=2;end
if(key_box && layout_profile!=2)begin if(x>=zone_x+6 && x<zone_x+6+4*16 && y>=344 && y<344+24)begin zh=0;text_x=zone_x+6;text_y=344;text_len=4;text=note_text(layout_profile,zone_index);font_double=1;ink=hit ? 3 : 1;end end
if(key_box && layout_profile==2)begin if(x>=zone_x+5 && x<zone_x+5+4*8 && y>=350 && y<350+12)begin zh=0;text_x=zone_x+5;text_y=350;text_len=4;text=note_text(layout_profile,zone_index);font_double=0;ink=hit ? 3 : 1;end end
if(x>=32 && x<32+2*24 && y>=400 && y<400+24)begin zh=1;text_x=32;text_y=400;text_len=2;label_id=28;ink=1;end
if(x>=88 && x<88+3*8 && y>=408 && y<408+12)begin zh=0;text_x=88;text_y=408;text_len=3;text=three(11);font_double=0;ink=2;end
if(x>=210 && x<210+2*24 && y>=400 && y<400+24)begin zh=1;text_x=210;text_y=400;text_len=2;label_id=29;ink=1;end
if(x>=266 && x<266+6*8 && y>=408 && y<408+12)begin zh=0;text_x=266;text_y=408;text_len=6;text={ui_status[79] ? 8'd45 : 8'd43,four(8),"C"};font_double=0;ink=1;end
if(x>=430 && x<430+3*24 && y>=400 && y<400+24)begin zh=1;text_x=430;text_y=400;text_len=3;label_id=30;ink=1;end
if(x>=512 && x<512+3*8 && y>=408 && y<408+12)begin zh=0;text_x=512;text_y=408;text_len=3;text=three(10);font_double=0;ink=1;end
 end
if(x>=32 && x<32+4*8 && y>=442 && y<442+12)begin zh=0;text_x=32;text_y=442;text_len=4;text="KEY0";font_double=0;ink=1;end
if(x>=72 && x<72+4*24 && y>=434 && y<434+24)begin zh=1;text_x=72;text_y=434;text_len=4;label_id=55;ink=1;end
if(x>=184 && x<184+4*8 && y>=442 && y<442+12)begin zh=0;text_x=184;text_y=442;text_len=4;text="KEY2";font_double=0;ink=1;end
if(x>=224 && x<224+4*24 && y>=434 && y<434+24)begin zh=1;text_x=224;text_y=434;text_len=4;label_id=33;ink=1;end
if(x>=340 && x<340+6*8 && y>=442 && y<442+12)begin zh=0;text_x=340;text_y=442;text_len=6;text="KEY1+2";font_double=0;ink=1;end
if(x>=396 && x<396+4*24 && y>=434 && y<434+24)begin zh=1;text_x=396;text_y=434;text_len=4;label_id=41;ink=1;end
 end
 // Split widget selection from glyph lookup. Background and blank/sync take
 // the SAME one-clock delay, so a tile/text edge cannot shift relative to DE.
 reg [9:0] dx,dy;
 reg zh_p,font_double_p;reg [5:0] text_len_p,label_id_p;
 reg [255:0] text_p;reg [1:0] ink_p;reg [23:0] background_p;
 reg [3:0] selected_note_p;reg selected_visible_p;reg [11:0] hit_notes_p;
 wire [5:0] position=zh_p ? dx/24 : font_double_p ? dx>>4 : dx>>3;
 wire [4:0] zh_col=dx-position*24;
 wire [15:0] wide_ch;wire [23:0] wide_bits;
 video_text_zh labels(.label_id(label_id_p),.position(position[4:0]),.ch(wide_ch));
 video_font_zh wide_font(.ch(wide_ch),.row(dy[4:0]),.bits(wide_bits));
 wire [7:0] ascii_ch=char_at(text_p,text_len_p,position);
 wire [3:0] ascii_row=font_double_p ? dy>>1 : dy;
 wire [2:0] ascii_col=font_double_p ? dx>>1 : dx;
 wire [7:0] ascii_bits;
 video_font latin_font(.ch(ascii_ch),.row(ascii_row),.bits(ascii_bits));
 wire text_hit=position<text_len_p && (zh_p ? zh_col<24 && wide_bits[23-zh_col] : ascii_bits[7-ascii_col]);
 wire left_border=(x==32 || x==350) && y>=96 && y<278 || (y==96 || y==277) && x>=32 && x<=350;
 wire right_border=(x==366 || x==607) && y>=96 && y<278 || (y==96 || y==277) && x>=366 && x<=607;
 wire banner_border=(x==32 || x==607) && y>=96 && y<140 || (y==96 || y==139) && x>=32 && x<=607;
 wire [8:0] cal_width=ui_status[232:227]*5;
 wire [8:0] velocity_width={1'b0,ui_status[111:104]}+{4'b0,ui_status[111:107]};
 reg [23:0] background;
 always @* begin
 background=0;
 if(raster_de)begin
 background=y[1:0]==0 ? 24'h080010 : 24'h0A0014;
 if(y==92 && x>=32 && x<608)background=24'h76205A;
 if(diagnostic_view)begin
  if((x>=32 && x<=350 || x>=366 && x<=607) && y>=96 && y<278)background=24'h10091F;
  if(left_border || right_border)background=24'h342146;
 end else begin
  if(x>=32 && x<608 && y>=96 && y<140)background=24'h10091F;
  if(banner_border)background=24'h342146;
  if(x>=32 && x<144 && y>=370 && y<374)background=x-32<(velocity_width>>1) ? 24'hFF006E : 24'h342146;
 end
 if(ui_status[8] && x>=48 && x<298 && y>=(diagnostic_view ? 270 : 135) && y<(diagnostic_view ? 273 : 138))
  background=x-48<cal_width ? 24'h00FFFF : 24'h342146;
 if(!diagnostic_view && x==320 && y>=343 && y<374)background=24'h00FFFF;
 if(key_box)begin
  background=hit ? 24'hFF006E : selected ? 24'h0C3A45 : 24'h10091F;
  if(key_edge)background=hit ? 24'hFFD8F0 : selected ? 24'h00FFFF : 24'h275A62;
 end
 end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   selected_note_p<=0;selected_visible_p<=0;hit_notes_p<=0;
   dx<=0;dy<=0;zh_p<=0;font_double_p<=0;text_len_p<=0;label_id_p<=0;
   text_p<=0;ink_p<=1;background_p<=0;de_p<=0;hsync_p<=1;vsync_p<=1;
  end else begin
   selected_note_p<=selected_note;selected_visible_p<=selected_visible;hit_notes_p<=hit_notes;
   dx<=x-text_x;dy<=y-text_y;zh_p<=zh;font_double_p<=font_double;
   text_len_p<=text_len;label_id_p<=label_id;text_p<=text;ink_p<=ink;
   background_p<=background;de_p<=raster_de;hsync_p<=raster_hsync;vsync_p<=raster_vsync;
  end
 end
 always @* begin
  {red,green,blue}=background_p;
  if(de_p && |fan_zones)begin
   {red,green,blue}=|(fan_zones & hit_notes_p) ? 24'hFF006E : selected_visible_p && fan_zones[selected_note_p] ? 24'h0C3A45 : 24'h10091F;
   if(fan_edge){red,green,blue}=|(fan_zones & hit_notes_p) ? 24'hFFD8F0 : selected_visible_p && fan_zones[selected_note_p] ? 24'h00FFFF : 24'h275A62;
  end
  // Solid text; scanlines stay behind the glyphs for readable WenKai strokes.
  if(de_p && text_hit){red,green,blue}=ink_p==1 ? 24'h00FFFF : ink_p==2 ? 24'hFF006E : 24'h0A0014;
 end
endmodule
