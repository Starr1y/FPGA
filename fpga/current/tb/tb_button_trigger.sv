`timescale 1ns/1ps
// Physical report cadence:250 core clocks at100kHz =2.5ms, timestamp step25.
module tb_button_trigger;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,pv=0,lv=0,gv=0,online=1,restarted=0,button_n=1;
 reg signed[15:0]z=0,yaw=0,gx=0,xy=0;
 reg[7:0]seq=0;reg[31:0]ts=0;integer hits=0,k;
 wire note_on;wire[1:0]reason;wire[3:0]zone;wire armed;
 gesture_control #(.CLK_HZ(100000),.BUTTON_TRIGGER(1)) d(.button_n(button_n),.clk(clk),.rst_n(rst_n),.sensor_restarted(restarted),.online(online),
 .calibrated(1'b1),.calibrating(1'b0),.accuracy(2'd3),.layout_profile(2'd0),.snapshot_required(1'b0),
 .snapshot_valid(1'b1),.snapshot_zone(4'd0),.snapshot_octave(2'd0),.snapshot_profile(2'd0),
 .pose_valid(pv),.yaw(yaw),.pitch(16'sd0),.roll(16'sd0),.accel_valid(lv),.gyro_valid(gv),.gravity_valid(1'b0),
 .linear_valid(lv),.linear_sequence(seq),.linear_timestamp_ticks(ts),.linear_timestamp_valid(1'b1),
 .lx(xy),.ly(xy),.lz(z),.ax(xy),.ay(xy),.az(16'sd0),
 .gx(gx),.gy(16'sd0),.gz(16'sd0),.gravity_x(16'sd0),.gravity_y(16'sd0),.gravity_z(16'sd0),
 .note_on(note_on),.last_trigger_reason(reason),.selected_zone(zone),.armed(armed));
 always @(posedge clk)if(note_on)begin
  hits=hits+1;
  if(reason!=0)$fatal(1,"strike missing jerk/down confirmation reason=%d",reason);
 end
 task sample(input integer down);begin
  @(negedge clk);z=-down;pv=1;lv=1;gv=1;seq=seq+1;ts=ts+25;
  @(negedge clk);pv=0;lv=0;gv=0;repeat(248)@(negedge clk);
 end endtask
 task settle;begin gx=0;repeat(60)sample(0);if(!armed)$fatal(1,"not rearmed after quiet");end endtask
 task expect_hits(input integer n);begin if(hits!=n)$fatal(1,"unexpected strike count got=%d expected=%d",hits,n);end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;settle();
  // A real downstroke must be silent in button mode.
  sample(900);sample(950);repeat(20)sample(0);expect_hits(0);
  gx=2000;for(k=0;k<=55;k=k+1)begin yaw=k*16;sample(0);end
  repeat(20)sample(0);if(zone!=5)$fatal(1,"selection failed");expect_hits(0);
  // Sub-debounce contact bounce is silent.
  button_n=0;sample(0);button_n=1;sample(0);button_n=0;sample(0);button_n=1;
  repeat(8)sample(0);expect_hits(0);
  button_n=0;repeat(8)sample(0);expect_hits(1);
  if(d.hit_zone!=5 || d.velocity!=96)$fatal(1,"button used wrong note/velocity");
  repeat(100)sample(1200);expect_hits(1);
  button_n=1;repeat(8)sample(0);button_n=0;repeat(8)sample(0);expect_hits(2);
  // Loss of link while held must not replay on return.
  online=0;repeat(8)sample(0);online=1;repeat(20)sample(0);expect_hits(2);
  button_n=1;repeat(8)sample(0);button_n=0;repeat(8)sample(0);expect_hits(3);
  online=0;button_n=1;repeat(8)sample(0);button_n=0;repeat(8)sample(0);
  online=1;repeat(20)sample(0);expect_hits(3);
  // Rejected/stale pose is not eligible, even with valid contact presses.
  button_n=1;repeat(5000)@(negedge clk);button_n=0;repeat(2000)@(negedge clk);expect_hits(3);
  repeat(20)sample(0);expect_hits(3);
  button_n=1;repeat(8)sample(0);button_n=0;repeat(8)sample(0);expect_hits(4);
  $display("TB_PASS button-only: selection/downstroke silent,bounce,one press one note,hold,release,reconnect-held,offline press,stale press");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
