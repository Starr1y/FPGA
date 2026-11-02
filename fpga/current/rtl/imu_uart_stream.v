// STM32 right-hand bridge. 38 bytes, 230400/8N1; no SHTP emulation.
// Timestamps are MCU acquisition time in 100us ticks, not UART arrival time.
module imu_uart_stream #(parameter CLK_HZ=50000000,BAUD=230400)(
 input clk,rst_n,force_reset,rx,quat_ready,linear_ready,
 output[31:0]timestamp_now,output reg online,sensor_restarted,
 output reg quat_valid,gyro_valid,linear_valid,
 output reg signed[15:0]qx,qy,qz,qw,gx,gy,gz,lx,ly,lz,
 output reg[7:0]sequence_id,output reg[31:0]sample_timestamp,
 output reg[1:0]accuracy,output reg[31:0]errors,gaps,
 output reg[15:0]packets,received_bytes,rate_hz
);
 wire[7:0]byte_data;wire byte_valid,byte_error;
 uart_rx #(.CLK_HZ(CLK_HZ)) receiver(.clk(clk),.rst_n(rst_n),.rx(rx),.baud(BAUD),
  .data(byte_data),.valid(byte_valid),.start(),.error(byte_error));
 reg[7:0]buf_q[0:35];reg[5:0]pos;reg[15:0]crc,crc_low;
 reg[31:0]interbyte,age,divider,ticks,rate_timer;reg[15:0]rate_count;
 reg seen;reg[15:0]last_sequence,last_boot;reg[31:0]last_stamp,last_arrival,stream_clock;
 reg[2:0]check_stage;reg[33:0]norm;reg signed[15:0]component;
 wire[15:0]frame_sequence={buf_q[7],buf_q[6]},frame_boot={buf_q[13],buf_q[12]};
 wire[31:0]frame_stamp={buf_q[11],buf_q[10],buf_q[9],buf_q[8]};
 wire[15:0]seq_delta=frame_sequence-last_sequence;
 wire[31:0]stamp_delta=frame_stamp-last_stamp;
 wire[31:0]arrival_delta=ticks-last_arrival;
 wire pace_ok=stamp_delta>arrival_delta ? stamp_delta-arrival_delta<=100 : arrival_delta-stamp_delta<=100;
 wire healthy=buf_q[14][2:0]==3'b111;
 // A session can also change after reconnect or an unannounced MCU reset.
 wire new_session=!seen || !online || frame_boot!=last_boot || $signed(stamp_delta)<0;
 // Extrapolate the MCU clock only between frames; reanchor on every valid
 // sample. A one-time absolute offset would drift with the STM32 HSI clock.
 // Jerk/history keep the original acquisition timestamps unchanged.
 // Incrementally maintain exactly the same extrapolated acquisition clock.
 // A valid frame reanchors this register; an intervening 100us tick adds one.
 // This removes subtract/add/subtract from the pose admission critical path.
 assign timestamp_now=seen ? stream_clock : ticks;
 function[15:0]crc_byte;input[15:0]old;input[7:0]b;integer n;reg[15:0]c;
 begin c=old^{b,8'd0};for(n=0;n<8;n=n+1)c=c[15] ? (c<<1)^16'h1021 : c<<1;crc_byte=c;end endfunction
 always @*begin
  case(check_stage)
   1:component={buf_q[17],buf_q[16]};2:component={buf_q[19],buf_q[18]};
   3:component={buf_q[21],buf_q[20]};default:component={buf_q[23],buf_q[22]};
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   pos<=0;crc<=16'hffff;crc_low<=0;interbyte<=0;age<=CLK_HZ;divider<=0;ticks<=0;
   rate_timer<=0;rate_count<=0;rate_hz<=0;seen<=0;last_sequence<=0;last_boot<=0;last_stamp<=0;last_arrival<=0;stream_clock<=0;
   check_stage<=0;norm<=0;online<=0;sensor_restarted<=0;quat_valid<=0;gyro_valid<=0;linear_valid<=0;
   qx<=0;qy<=0;qz<=0;qw<=16384;gx<=0;gy<=0;gz<=0;lx<=0;ly<=0;lz<=0;
   sequence_id<=0;sample_timestamp<=0;accuracy<=0;errors<=0;gaps<=0;packets<=0;received_bytes<=0;
  end else begin
   quat_valid<=0;gyro_valid<=0;linear_valid<=0;sensor_restarted<=0;
   if(divider==CLK_HZ/10000-1)begin divider<=0;ticks<=ticks+1'b1;stream_clock<=stream_clock+1'b1;end else divider<=divider+1'b1;
   if(age<CLK_HZ)age<=age+1'b1;
   if(age>=CLK_HZ/10)begin online<=0;accuracy<=0;end
   if(rate_timer==CLK_HZ-1)begin rate_timer<=0;rate_hz<=rate_count;rate_count<=0;end else rate_timer<=rate_timer+1'b1;
   if(pos!=0)begin
    if(interbyte>=CLK_HZ/100)begin pos<=0;interbyte<=0;errors<=errors+1'b1;end else interbyte<=interbyte+1'b1;
   end
   if(byte_error)begin pos<=0;errors<=errors+1'b1;end
   if(byte_valid)begin
    received_bytes<=received_bytes+1'b1;interbyte<=0;
    if(pos==0)begin if(byte_data==8'ha5)pos<=1;end
    else if(pos==1)begin
     if(byte_data==8'h5a)begin pos<=2;crc<=16'hffff;end
     else pos<=byte_data==8'ha5 ? 1 : 0;
    end else if(pos<=35)begin buf_q[pos]<=byte_data;crc<=crc_byte(crc,byte_data);pos<=pos+1'b1;end
    else if(pos==36)begin crc_low<={8'd0,byte_data};pos<=37;end
    else begin
     pos<=0;
     if({byte_data,crc_low[7:0]}!=crc || buf_q[2]!=1 || buf_q[3]!=1 ||
        {buf_q[5],buf_q[4]}!=30 || buf_q[15]!=1 || check_stage!=0)errors<=errors+1'b1;
     else if(!healthy)begin
      if(online)sensor_restarted<=1;
      online<=0;accuracy<=0;seen<=0;
     end else begin check_stage<=1;norm<=0;end
    end
   end
   if(check_stage>=1 && check_stage<=4)begin
    norm<=norm+$unsigned($signed({{16{component[15]}},component})*$signed({{16{component[15]}},component}));
    check_stage<=check_stage+1'b1;
   end else if(check_stage==5)begin
    check_stage<=0;
    if(norm<34'd214748364 || norm>34'd322122547 || !quat_ready || !linear_ready)errors<=errors+1'b1;
    else if(!new_session && (seq_delta==0 || seq_delta[15] || stamp_delta<20 || stamp_delta>400 || !pace_ok))errors<=errors+1'b1;
    else begin
     if(new_session)begin sample_timestamp<=frame_stamp;sensor_restarted<=1;end
     else begin
      sample_timestamp<=frame_stamp;
      if(seq_delta!=1)gaps<=gaps+1'b1;
     end
     last_sequence<=frame_sequence;last_stamp<=frame_stamp;last_boot<=frame_boot;last_arrival<=ticks;seen<=1;
     // Nonblocking ticks also advances on a tick-edge arrival. Include that
     // tick to preserve last_stamp+(ticks-last_arrival), including wraparound.
     stream_clock<=frame_stamp+(divider==CLK_HZ/10000-1 ? 32'd1 : 32'd0);
     qx<={buf_q[17],buf_q[16]};qy<={buf_q[19],buf_q[18]};qz<={buf_q[21],buf_q[20]};qw<={buf_q[23],buf_q[22]};
     lx<={buf_q[25],buf_q[24]};ly<={buf_q[27],buf_q[26]};lz<={buf_q[29],buf_q[28]};
     gx<={buf_q[31],buf_q[30]};gy<={buf_q[33],buf_q[32]};gz<={buf_q[35],buf_q[34]};
     sequence_id<=frame_sequence[7:0];accuracy<=2;online<=1;age<=0;
     // The first frame resets the common pipeline. Publish on the next frame.
     if(!new_session)begin quat_valid<=1;gyro_valid<=1;linear_valid<=1;end
     packets<=packets+1'b1;if(rate_count!=65535)rate_count<=rate_count+1'b1;
    end
   end
   if(force_reset)begin
    seen<=0;online<=0;accuracy<=0;pos<=0;check_stage<=0;age<=CLK_HZ;
    quat_valid<=0;gyro_valid<=0;linear_valid<=0;sensor_restarted<=1;
   end
  end
 end
endmodule
