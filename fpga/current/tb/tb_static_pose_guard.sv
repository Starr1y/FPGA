`timescale 1ns/1ps
module tb_static_pose_guard;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,pv=0,lv=0,gv=0;reg signed[15:0]yaw=0,gx=0;
 reg[7:0]seq=0;reg[31:0]ts=0;
 wire[3:0]zone;wire fresh,playable,armed,note_on,range_bad,drift;
`ifdef MOTIONFIX_BASELINE
 wire rejection_count_ok=1'b1;
`else
 wire rejection_count_ok=d.pose_rejections==1;
`endif
 gesture_control #(.CLK_HZ(1000)) d(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.online(1'b1),
 .calibrated(1'b1),.calibrating(1'b0),.accuracy(2'd3),.layout_profile(2'd0),
 .snapshot_required(1'b0),.snapshot_valid(1'b1),.snapshot_zone(4'd0),.snapshot_octave(2'd0),.snapshot_profile(2'd0),
 .pose_valid(pv),.yaw(yaw),.pitch(16'sd0),.roll(16'sd0),.accel_valid(lv),.gyro_valid(gv),.gravity_valid(1'b0),
 .linear_valid(lv),.linear_sequence(seq),.linear_timestamp_ticks(ts),.linear_timestamp_valid(1'b1),
 .lx(16'sd0),.ly(16'sd0),.lz(16'sd0),.ax(16'sd0),.ay(16'sd0),.az(16'sd0),
 .gx(gx),.gy(16'sd0),.gz(16'sd0),.gravity_x(16'sd0),.gravity_y(16'sd0),.gravity_z(16'sd0),
 .selected_zone(zone),.data_fresh(fresh),.playable(playable),.armed(armed),.note_on(note_on),.out_of_range(range_bad),.drift_warning(drift));
 task sample(input integer angle,rate);begin
  @(negedge clk);yaw=angle*16;gx=rate;pv=1;lv=1;gv=1;seq=seq+1;ts=ts+50;
  @(negedge clk);pv=0;lv=0;gv=0;repeat(3)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(15)sample(0,0);
  if(zone!=3 || !playable)$fatal(1,"not ready");
  sample(96,0);
  if(range_bad || drift || zone!=3 || note_on || armed || !rejection_count_ok)$fatal(1,"isolated stationary yaw glitch changed control state");
  repeat(15)sample(0,0);if(!playable)$fatal(1,"glitch recovery failed");
  repeat(16)sample(70,2000);if(zone!=6 || !playable)$fatal(1,"real turn suppressed");
  repeat(12)sample(89,2000);if(range_bad)$fatal(1,"89deg in range");
  repeat(6)sample(92,2000);if(!range_bad || playable)$fatal(1,"real out of range allowed");
  repeat(12)begin sample(89,0);sample(91,0);end
  if(!range_bad || playable)$fatal(1,"range boundary jitter re-enabled playing");
  repeat(12)sample(80,2000);if(range_bad || !playable)$fatal(1,"return to range failed");
  // Continuous corrupted poses must expire, never keep the instrument playable.
  repeat(12)sample(86,0);if(fresh || playable || note_on)$fatal(1,"rejected poses refreshed freshness");
  $display("TB_PASS isolated static glitch, real turn, range hysteresis, persistent invalid poses");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
