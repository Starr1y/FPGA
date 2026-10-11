`timescale 1ns/1ps
// Native SH-2 cargo bytes -> real decoder -> Z trigger, including batch timing.
module tb_z_reports;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;
 reg packet_ready=0;reg [9:0]packet_length=19;reg [7:0]memory[0:511];
 wire packet_take;wire [8:0]read_addr;wire [7:0]read_data=memory[read_addr];
 reg [31:0]packet_hint_ticks=0;
 wire linear_valid,linear_timestamp_valid;wire [31:0]linear_timestamp_ticks;
 wire [7:0]linear_sequence;wire signed [15:0]lx,ly,lz;
 reg pose_valid=0,gyro_valid=0;reg [7:0]cargo_seq=0,sample_seq=0;
 wire note_on,armed,data_fresh;wire [31:0]hit_count;wire [1:0]last_trigger_reason;
 shtp_report_decode #(.REPORT_BACKPRESSURE(1)) decoder(.clk(clk),.rst_n(rst_n),.packet_ready(packet_ready),.packet_length(packet_length),
  .packet_hint_ticks(packet_hint_ticks),.packet_hint_valid(1'b1),.linear_ready(1'b1),
  .packet_take(packet_take),.read_addr(read_addr),.read_data(read_data),.linear_valid(linear_valid),
  .linear_timestamp_ticks(linear_timestamp_ticks),.linear_timestamp_valid(linear_timestamp_valid),.linear_sequence(linear_sequence),.lx(lx),.ly(ly),.lz(lz));
 gesture_control #(.CLK_HZ(100000)) gestures(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.online(1'b1),.calibrated(1'b1),.calibrating(1'b0),
  .accuracy(2'd3),.layout_profile(2'd0),.pose_valid(pose_valid),.yaw(16'sd0),.pitch(16'sd0),.roll(16'sd0),
  .accel_valid(1'b0),.gyro_valid(gyro_valid),.gravity_valid(1'b0),.ax(16'sd0),.ay(16'sd0),.az(16'sd2510),
  .gx(16'sd0),.gy(16'sd0),.gz(16'sd0),.gravity_x(16'sd0),.gravity_y(16'sd0),.gravity_z(16'sd2510),
  .linear_valid(linear_valid),.linear_sequence(linear_sequence),.linear_timestamp_valid(linear_timestamp_valid),.linear_timestamp_ticks(linear_timestamp_ticks),
  .lx(lx),.ly(ly),.lz(lz),.note_on(note_on),.hit_count(hit_count),.last_trigger_reason(last_trigger_reason),.armed(armed),.data_fresh(data_fresh));
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 task fill(input integer offset,input integer delay_ticks,input integer down);
  integer z;begin
   z=-down;memory[offset]=4;memory[offset+1]=sample_seq;sample_seq++;
   memory[offset+2]=3 | ((delay_ticks>>8)<<2);memory[offset+3]=delay_ticks;
   memory[offset+8]=z;memory[offset+9]=z>>>8;
  end
 endtask
 task cargo(input integer down,input integer dt);
  begin
   for(integer n=0;n<512;n++)memory[n]=0;
   packet_hint_ticks+=dt;memory[0]=19;memory[2]=3;memory[3]=cargo_seq;cargo_seq++;
   memory[4]=8'hfb;fill(9,0,down);packet_length=19;
   pose_valid=1;gyro_valid=1;tick(1);pose_valid=0;gyro_valid=0;
   packet_ready=1;wait(packet_take);tick(1);packet_ready=0;tick(930);
  end
 endtask
 integer before_hits;
 initial begin
  tick(5);rst_n=1;repeat(5)cargo(0,100);
  if(!armed)$fatal(1,"native bytes did not arm");
  cargo(256,100);if(hit_count!=1 || last_trigger_reason!=2)$fatal(1,"native linear jerk did not fire");
  repeat(15)cargo(0,100);before_hits=hit_count;
  // Reports parsed microseconds apart but sampled 20ms apart: below jerk threshold.
  for(integer n=0;n<512;n++)memory[n]=0;
  packet_hint_ticks+=500;memory[0]=39;memory[2]=3;memory[3]=cargo_seq;cargo_seq++;
  memory[4]=8'hfb;memory[5]=400;memory[6]=400>>8;
  fill(9,0,0);fill(19,200,256);fill(29,400,512);packet_length=39;
  pose_valid=1;gyro_valid=1;tick(1);pose_valid=0;gyro_valid=0;
  packet_ready=1;wait(packet_take);tick(1);packet_ready=0;tick(100);
  if(hit_count!=before_hits)$fatal(1,"batched arrival time used as sample dt");
  repeat(15)cargo(0,100);sample_seq++;before_hits=hit_count;cargo(1024,100);
  if(hit_count!=before_hits || data_fresh)$fatal(1,"native report sequence gap triggered");
  repeat(15)cargo(0,100);before_hits=hit_count;
  cargo(-256,100);cargo(-128,50);
  if(hit_count!=before_hits+1 || last_trigger_reason!=2 || lz<=0)
   $fatal(1,"native independent negative jerk with positive Z acceleration failed");
  $display("TB_PASS native linear SH2 bytes, base/delay timestamps, batch report cadence independent of arrival, directional jerk and sequence gap suppression");$finish;
 end
 initial begin #3000000;$fatal(1,"Z report watchdog");end
endmodule
