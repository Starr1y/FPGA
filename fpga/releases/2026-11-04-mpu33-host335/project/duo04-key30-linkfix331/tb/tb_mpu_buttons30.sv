`timescale 1ns/1ps
`include "tb/mpu6050_peer.sv"
module tb_mpu_buttons30;
 reg[1:0]button_valid=0;reg[63:0]button_data=0;
 reg clk=0;always #10 clk=~clk;reg rst=0;reg[1:0]calibrate=0,force_reset=0;reg right_connected=0;
 tri1[1:0]scl,sda;wire[1:0]scl_low,sda_low,online,release_pending;wire[511:0]status;
 reg signed[15:0]left_z=4096,right_z=4096;wire event_valid;wire[63:0]event_data;integer left_hits=0,right_hits=0;
 genvar i;generate for(i=0;i<2;i=i+1)begin:pad
 assign scl[i]=scl_low[i]?0:1'bz;assign sda[i]=sda_low[i]?0:1'bz;
 end endgenerate
 mpu6050_peer left(.scl(scl[0]),.sda(sda[0]),.connected(1'b1),.ax(16'sd0),.ay(16'sd0),.az(left_z),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0));
 mpu6050_peer #(.ADDRESS(7'h69)) right(.scl(scl[1]),.sda(sda[1]),.connected(right_connected),.ax(16'sd0),.ay(16'sd0),.az(right_z),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0));
 two_hand_i2c_core #(.CLK_HZ(1000000),.HALF_DIV(2),.BOOT_TICKS(20)) dut(
 .button_valid(button_valid),.button_data(button_data),.clk(clk),.rst_n(rst),.enabled(2'b11),.force_reset(force_reset),.calibrate(calibrate),.express(2'b00),.mirror(2'b00),.layout_profile(4'b0),
 .scl_in(scl),.sda_in(sda),.int_n(2'b11),.wrist_enable(2'b00),.wrist_fresh(2'b00),.wrist_octaves(4'b0),
 .scl_low(scl_low),.sda_low(sda_low),.online(online),.status(status),.event_valid(event_valid),.event_ready(1'b1),.event_data(event_data),.release_pending(release_pending),.release_ack(release_pending));
 defparam dut.hand[0].endpoint.host.BIAS_LOG2=3;
 defparam dut.hand[0].endpoint.host.WARMUP_SAMPLES=20;
 defparam dut.hand[1].endpoint.host.BIAS_LOG2=3;
 defparam dut.hand[1].endpoint.host.WARMUP_SAMPLES=20;
 always @(posedge clk)if(event_valid && event_data[31:30]==0)begin if(event_data[29])right_hits<=right_hits+1;else left_hits<=left_hits+1;end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  wait(online[0]);repeat(180000)@(negedge clk);
  if(online[1])$fatal(1,"disconnected right falsely online");
  calibrate=1;@(negedge clk);calibrate=0;
  wait(status[1] && status[4] && status[3]);repeat(10000)@(negedge clk);
  left_z=2048;repeat(20000)@(negedge clk);left_z=4096;
  if(left_hits!=0)$fatal(1,"acceleration still triggers audio");
  button_data[20:14]=80;button_data[11:4]=1;button_valid=1;@(negedge clk);button_valid=0;
  wait(left_hits==1);if(right_hits!=0)$fatal(1,"right cross-trigger");
  right_connected=1;force_reset=2;@(negedge clk);force_reset=0;
  wait(online[1]);repeat(180000)@(negedge clk);calibrate=2;@(negedge clk);calibrate=0;
  wait(status[257] && status[260] && status[259]);repeat(10000)@(negedge clk);
  right_z=2048;repeat(20000)@(negedge clk);right_z=4096;
  if(right_hits!=0)$fatal(1,"right acceleration triggers audio");
  button_data[52:46]=80;button_data[43:36]=1;button_valid=2;@(negedge clk);button_valid=0;
  wait(right_hits==1);if(!online[0] || left_hits!=1)$fatal(1,"independent hand lost");
  $display("TB_PASS dual MPU address68/69/calibration; acceleration produces zero notes, independent button events work");$finish;
 end
 initial begin #80000000;$fatal(1,"watchdog online%b status%h hits%d/%d",online,status[31:0],left_hits,right_hits);end
endmodule
