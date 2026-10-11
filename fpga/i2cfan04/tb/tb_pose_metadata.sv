`timescale 1ns/1ps
module tb_pose_metadata;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,quat_valid=0,quat_timestamp_valid=1;
 reg [7:0]quat_sequence=17;reg[31:0]quat_timestamp_ticks=12345;
 wire pose_valid,pose_timestamp_valid;wire[7:0]pose_sequence;wire[31:0]pose_timestamp_ticks;wire[31:0]overruns;
 quaternion_pose dut(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.online(1'b1),.calibrate(1'b0),
  .quat_valid(quat_valid),.qx(16'sd0),.qy(16'sd0),.qz(16'sd0),.qw(16'sd16384),.accuracy(2'd3),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0),
  .quat_sequence(quat_sequence),.quat_timestamp_ticks(quat_timestamp_ticks),.quat_timestamp_valid(quat_timestamp_valid),
  .pose_valid(pose_valid),.pose_sequence(pose_sequence),.pose_timestamp_ticks(pose_timestamp_ticks),.pose_timestamp_valid(pose_timestamp_valid),.overruns(overruns));
 task pulse;begin @(negedge clk);quat_valid=1;@(negedge clk);quat_valid=0;end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;pulse();
  quat_sequence=99;quat_timestamp_ticks=99999;quat_timestamp_valid=0;pulse();
  wait(pose_valid);@(negedge clk);
  if(pose_sequence!=17 || pose_timestamp_ticks!=12345 || !pose_timestamp_valid || overruns!=1)
   $fatal(1,"busy sample replaced metadata of accepted quaternion");
  quat_sequence=18;quat_timestamp_ticks=12445;quat_timestamp_valid=0;pulse();
  wait(pose_valid);@(negedge clk);
  if(pose_sequence!=18 || pose_timestamp_ticks!=12445 || pose_timestamp_valid)$fatal(1,"invalid timestamp flag did not propagate");
  $display("TB_PASS accepted quaternion owns pose metadata, in-flight overrun cannot replace metadata, invalid timestamp flag preserved");$finish;
 end
 initial begin #100000;$fatal(1,"pose metadata watchdog");end
endmodule
