`timescale 1ns/1ps
// Physical report cadence:250 core clocks at100kHz =2.5ms, timestamp step25.
module tb_motion_trigger_paths;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,pv=0,lv=0,gv=0,online=1,restarted=0;
 reg signed[15:0]z=0,yaw=0,gx=0,xy=0;
 reg[7:0]seq=0;reg[31:0]ts=0;integer hits=0,k;
 wire note_on;wire[1:0]reason;wire[3:0]zone;wire armed;
 gesture_control #(.CLK_HZ(100000)) d(.clk(clk),.rst_n(rst_n),.sensor_restarted(restarted),.online(online),
 .calibrated(1'b1),.calibrating(1'b0),.accuracy(2'd3),.layout_profile(2'd0),.snapshot_required(1'b0),
 .snapshot_valid(1'b1),.snapshot_zone(4'd0),.snapshot_octave(2'd0),.snapshot_profile(2'd0),
 .pose_valid(pv),.yaw(yaw),.pitch(16'sd0),.roll(16'sd0),.accel_valid(lv),.gyro_valid(gv),.gravity_valid(1'b0),
 .linear_valid(lv),.linear_sequence(seq),.linear_timestamp_ticks(ts),.linear_timestamp_valid(1'b1),
 .lx(xy),.ly(xy),.lz(z),.ax(xy),.ay(xy),.az(16'sd0),
 .gx(gx),.gy(16'sd0),.gz(16'sd0),.gravity_x(16'sd0),.gravity_y(16'sd0),.gravity_z(16'sd0),
 .note_on(note_on),.last_trigger_reason(reason),.selected_zone(zone),.armed(armed));
 always @(posedge clk)if(note_on)begin
  hits=hits+1;
  if(reason!=3)$fatal(1,"strike missing jerk/down confirmation reason=%d",reason);
 end
 task sample(input integer down);begin
  @(negedge clk);z=-down;pv=1;lv=1;gv=1;seq=seq+1;ts=ts+25;
  @(negedge clk);pv=0;lv=0;gv=0;repeat(248)@(negedge clk);
 end endtask
 task settle;begin gx=0;repeat(60)sample(0);if(!armed)$fatal(1,"not rearmed after quiet");end endtask
 task expect_hits(input integer n);begin if(hits!=n)$fatal(1,"unexpected strike count got=%d expected=%d",hits,n);end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;settle();
  // Selection over several sectors changes the selection without a note.
  gx=2000;for(k=0;k<=55;k=k+1)begin yaw=k*16;sample(0);end
  repeat(20)sample(0);if(zone!=5)$fatal(1,"selection failed %d",zone);expect_hits(0);
  settle();
  // Static Q8 noise and a jerk above threshold but below down amplitude.
  for(k=0;k<80;k=k+1)sample((k%2)?24:-24);
  sample(100);sample(180);sample(0);expect_hits(0);
  // Full isolated spike must not strike, even though jerk and amplitude pass.
  sample(1500);sample(0);repeat(4)sample(0);expect_hits(0);
  // Upward acceleration easing back towards zero is not a down strike.
  sample(-1200);sample(-800);sample(-400);sample(0);expect_hits(0);
  // Large X/Y acceleration and rotation alone are silent.
  xy=5000;repeat(8)sample(0);xy=0;expect_hits(0);
  // Slow downward acceleration passes amplitude but never jerk threshold.
  settle();for(k=1;k<=45;k=k+1)sample(k*20);
  repeat(50)sample(900);expect_hits(0);
  // Clear down jerk followed by a second downward report strikes exactly once.
  settle();sample(900);expect_hits(0);sample(950);expect_hits(1);
  repeat(80)sample(950);expect_hits(1); // held/refractory never retriggers
  settle();sample(950);sample(1000);expect_hits(2);
  // Gap between candidate and confirmation invalidates derivative/candidate.
  settle();sample(1000);seq=seq+1;sample(1000);sample(1000);expect_hits(2);
  // Offline clears both history and pending trigger; no replay at reconnect.
  settle();sample(1000);online=0;sample(1000);online=1;
  sample(1000);sample(1000);expect_hits(2);
  settle();sample(1000);restarted=1;sample(1000);restarted=0;
  sample(1000);sample(1000);expect_hits(2);
  settle();sample(900);sample(900);expect_hits(3);
  $display("TB_PASS selection silent; static noise,subthreshold jerk,isolated spike,upward braking,XY and slow press silent; confirmed down jerk,hold,rearm,gap,offline,restart");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
