module top(input clk,input reset_key,input pc_rx,output pc_tx,
 input imu_data,input imu_int_n,output imu_clk_tx,output imu_cs_n,output imu_mosi,output imu_rst_n,output imu_wake,
 output hp_bck,output hp_ws,output hp_din,output pa_en,output event_mark,output audio_mark);
 localparam CLK_HZ=50000000;
 reg [19:0] boot=0;reg [1:0] reset_sync=0;
 wire rst_n=boot[19] && !reset_sync[1];
 always @(posedge clk)begin reset_sync<={reset_sync[0],reset_key};if(!boot[19])boot<=boot+1;end
 reg [31:0] ticks;always @(posedge clk)if(!rst_n)ticks<=0;else ticks<=ticks+1;
 assign pa_en=0;
 wire [7:0] rx_data;wire rx_valid,rx_start,rx_error;
 uart_rx #(.CLK_HZ(CLK_HZ)) pc_uart_rx(clk,rst_n,pc_rx,32'd921600,rx_data,rx_valid,rx_start,rx_error);
 wire cmd_done;wire [7:0] cmd;wire [15:0] cmd_seq;wire [6:0] cmd_len;wire [511:0] cmd_data;wire [31:0] cmd_errors;
 frame_rx command_rx(clk,rst_n,rx_data,rx_valid,cmd_done,cmd,cmd_seq,cmd_len,cmd_data,cmd_errors);
 wire voice_config=cmd_done && cmd==16 && (cmd_len==16 || cmd_len==17) && cmd_data[7:0]<4;
 // Legacy 8-bit gain is expanded by 257; new packets append its high byte.
 wire [135:0] voice_data=cmd_len==17?cmd_data[135:0]:{cmd_data[47:40],cmd_data[127:0]};
 assign event_mark=voice_config;
 wire sample_tick,sample_valid;wire [79:0] samples;wire [31:0] clips;
 wire piano_config=cmd_done && cmd==22 && cmd_len==4 && cmd_data[7:0]<4 && cmd_data[15:8]<2 && cmd_data[31:16]>0 && cmd_data[31:16]<=4096;
 audio_core audio(clk,rst_n,sample_tick,voice_config,voice_data,samples,sample_valid,clips,piano_config,cmd_data[31:0]);
 // Fixed headphone attenuation: digital capture remains pre-attenuation.
 wire signed [15:0] headphone_pcm=$signed(samples[79:64]) >>> 5;
 i2s_output #(.CLK_HZ(CLK_HZ)) i2s(clk,rst_n,headphone_pcm,hp_bck,hp_ws,hp_din,sample_tick);
 assign audio_mark=sample_tick;
 wire mode_valid=cmd_done && cmd==18 && cmd_len==1 && cmd_data[7:0]<3;
 wire imu_tx_busy;wire imu_tx_req=cmd_done && cmd==19 && cmd_len>0 && !imu_tx_busy;
 wire imu_ready;reg imu_take;wire [9:0] imu_len;wire [7:0] imu_byte;wire [31:0] imu_t0,imu_t1,imu_t2,imu_drops;wire [1:0] imu_mode;
 wire [15:0] tx_addr;
 wire [9:0] imu_addr=tx_addr-13;
 imu_transport #(.CLK_HZ(CLK_HZ)) imu(clk,rst_n,ticks,mode_valid,cmd_data[1:0],imu_tx_req,cmd_len,cmd_data,imu_tx_busy,
 imu_data,imu_int_n,imu_clk_tx,imu_cs_n,imu_mosi,imu_rst_n,imu_wake,imu_ready,imu_take,imu_len,imu_addr,imu_byte,imu_t0,imu_t1,imu_t2,imu_drops,imu_mode);
 reg [79:0] capture_mem[0:2047];reg [10:0] cap_wr;reg capture_active,armed,cap_ready;reg [15:0] capture_id,upload_offset;
 reg [15:0] capture_points;
 reg signed [15:0] previous_mix;
 reg [79:0] cap_word;
 wire [15:0] sample_index=upload_offset+(tx_addr-10)/10;
 always @(posedge clk)cap_word<=capture_mem[sample_index[10:0]];
 reg preview_on;reg [8:0] preview_count;
 reg signed [15:0] minima[0:4],maxima[0:4];
 reg [159:0] envelope;reg envelope_ready;integer j;
 reg [31:0] status_timer;reg status_pending;
 reg response_pending;reg [7:0] response_kind,response_code;reg [15:0] response_seq;
 reg tx_start;reg [7:0] tx_kind;reg [15:0] tx_len;reg [7:0] tx_payload;
 wire [7:0] tx_byte;wire tx_valid,tx_uart_ready,tx_busy,tx_done;
 reg [15:0] saved_seq;reg [7:0] saved_code;reg [31:0] saved_tick;
 frame_tx transmitter(clk,rst_n,tx_start,tx_kind,tx_len,saved_tick,tx_addr,tx_payload,tx_byte,tx_valid,tx_uart_ready,tx_busy,tx_done);
 uart_tx #(.CLK_HZ(CLK_HZ)) pc_uart_tx(clk,rst_n,32'd921600,tx_byte,tx_valid,tx_uart_ready,pc_tx);
 reg [31:0] tx_drops;reg [31:0] snap_drops,snap_clips;
 // Allow the onboard USB-UART bridge to drain between capture packets.
 reg [19:0] capture_gap;
 reg [159:0] snap_envelope;
 wire [31:0] sample_rate=48000;wire [31:0] clock_rate=CLK_HZ;
 reg [255:0] info_bytes;
 always @*begin
  info_bytes=0;
  info_bytes[15:0]=saved_seq;info_bytes[47:16]=clock_rate;info_bytes[79:48]=sample_rate;
  info_bytes[87:80]=4;info_bytes[103:88]=2048;
  info_bytes[111:104]="T";info_bytes[119:112]="a";info_bytes[127:120]="n";info_bytes[135:128]="g";
  info_bytes[143:136]="L";info_bytes[151:144]="a";info_bytes[159:152]="b";info_bytes[167:160]=" ";
  info_bytes[175:168]="1";info_bytes[183:176]=".";info_bytes[191:184]="3";
  info_bytes[199:192]=".";info_bytes[207:200]="1";
  tx_payload=0;
  case(tx_kind)
   128:tx_payload=info_bytes[tx_addr*8+:8];
   129,134:case(tx_addr)0:tx_payload=saved_seq[7:0];1:tx_payload=saved_seq[15:8];2:tx_payload=saved_code;endcase
   130:case(tx_addr)
    0:tx_payload=capture_id[7:0];1:tx_payload=capture_id[15:8];
    2:tx_payload=upload_offset[7:0];3:tx_payload=upload_offset[15:8];
    4:tx_payload=capture_points[7:0];5:tx_payload=capture_points[15:8];6:tx_payload=sample_rate[7:0];7:tx_payload=sample_rate[15:8];8:tx_payload=0;9:tx_payload=0;
    default:tx_payload=cap_word[((tx_addr-10)%10)*8+:8];
   endcase
   131:tx_payload=snap_envelope[tx_addr*8+:8];
   132:begin
    if(tx_addr==0)tx_payload={6'b0,imu_mode};
    else if(tx_addr<5)tx_payload=imu_t0[(tx_addr-1)*8+:8];
    else if(tx_addr<9)tx_payload=imu_t1[(tx_addr-5)*8+:8];
    else if(tx_addr<13)tx_payload=imu_t2[(tx_addr-9)*8+:8];
    else tx_payload=imu_byte;
   end
   133:if(tx_addr<4)tx_payload=snap_drops[tx_addr*8+:8];else tx_payload=snap_clips[(tx_addr-4)*8+:8];
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   capture_gap<=0;capture_points<=2048;
   capture_active<=0;armed<=0;cap_ready<=0;cap_wr<=0;capture_id<=0;upload_offset<=0;previous_mix<=0;
   preview_on<=0;preview_count<=0;envelope<=0;envelope_ready<=0;status_timer<=0;status_pending<=0;
   response_pending<=0;response_kind<=0;response_code<=0;response_seq<=0;tx_start<=0;tx_kind<=0;tx_len<=0;imu_take<=0;
   saved_seq<=0;saved_code<=0;saved_tick<=0;tx_drops<=0;snap_drops<=0;snap_clips<=0;snap_envelope<=0;
   for(j=0;j<5;j=j+1)begin minima[j]<=32767;maxima[j]<=-32768;end
  end else begin
   tx_start<=0;imu_take<=0;
   if(capture_gap!=0)capture_gap<=capture_gap-1;
   if(status_timer==CLK_HZ-1)begin status_timer<=0;status_pending<=1;end else status_timer<=status_timer+1;
   if(sample_valid)begin
    previous_mix<=samples[79:64];
    if(armed && previous_mix<0 && $signed(samples[79:64])>=0)begin armed<=0;capture_active<=1;cap_wr<=0;end
    if(capture_active)begin
     capture_mem[cap_wr]<=samples;
     if({5'b0,cap_wr}==capture_points-1'b1)begin capture_active<=0;cap_ready<=1;upload_offset<=0;end else cap_wr<=cap_wr+1;
    end
    for(j=0;j<5;j=j+1)begin
     if($signed(samples[j*16+:16])<minima[j])minima[j]<=samples[j*16+:16];
     if($signed(samples[j*16+:16])>maxima[j])maxima[j]<=samples[j*16+:16];
     if(preview_count==479)begin
      envelope[j*32+:16]<=$signed(samples[j*16+:16])<minima[j]?samples[j*16+:16]:minima[j];
      envelope[j*32+16+:16]<=$signed(samples[j*16+:16])>maxima[j]?samples[j*16+:16]:maxima[j];
      minima[j]<=32767;maxima[j]<=-32768;
     end
    end
    if(preview_count==479)begin preview_count<=0;if(preview_on)envelope_ready<=1;end else preview_count<=preview_count+1;
   end
   if(cmd_done)begin
    if(response_pending)tx_drops<=tx_drops+1;
    response_pending<=1;response_seq<=cmd_seq;response_kind<=129;response_code<=0;
    case(cmd)
     1:response_kind<=128;
     16:if((cmd_len!=16 && cmd_len!=17) || cmd_data[7:0]>3)response_code<=2;
     17:if((cmd_len!=1 && cmd_len!=3) || cmd_data[7:0]>1 || (cmd_len==3 && cmd_data[23:8]!=512 && cmd_data[23:8]!=2048))response_code<=2;
        else if(capture_active || armed || cap_ready)response_code<=1;
        else begin capture_id<=capture_id+1;cap_wr<=0;armed<=cmd_data[0];capture_active<=!cmd_data[0];capture_points<=cmd_len==3?cmd_data[23:8]:16'd2048;end
     18:if(cmd_len!=1 || cmd_data[7:0]>2)response_code<=2;
     19:if(imu_tx_busy)response_code<=1;else if(cmd_len==0 || imu_mode==0)response_code<=2;
     20:response_kind<=134;
     21:preview_on<=cmd_data[0];
     22:if(!piano_config)response_code<=2;
     default:response_code<=2;
    endcase
   end
   if(!tx_busy && !tx_start && !tx_done)begin
    saved_tick<=ticks;
    if(response_pending)begin
     saved_seq<=response_seq;saved_code<=response_code;tx_kind<=response_kind;tx_len<=response_kind==128?26:3;
     tx_start<=1;response_pending<=0;
    end else if(imu_ready && !imu_take)begin tx_kind<=132;tx_len<=imu_len+13;tx_start<=1;end
    else if(status_pending)begin tx_kind<=133;tx_len<=8;snap_drops<=imu_drops+tx_drops+cmd_errors;snap_clips<=clips;status_pending<=0;tx_start<=1;end
    else if(envelope_ready && preview_on)begin tx_kind<=131;tx_len<=20;snap_envelope<=envelope;envelope_ready<=0;tx_start<=1;end
    else if(cap_ready && capture_gap==0)begin tx_kind<=130;tx_len<=330;tx_start<=1;end
   end
   if(tx_done)begin
    if(tx_kind==132)imu_take<=1;
    if(tx_kind==130)begin
     capture_gap<=CLK_HZ/100; // 10 ms; sample acquisition remains 48 kHz.
     if(upload_offset==capture_points-16'd32)cap_ready<=0;else upload_offset<=upload_offset+32;
    end
   end
  end
 end
endmodule
