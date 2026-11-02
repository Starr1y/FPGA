`timescale 1ns/1ps
module tb_yforward_heading;
reg clk=0;always #5 clk=~clk;
reg rst=0,cal=0,sv=0;reg signed[15:0]qx,qy,qz,qw;reg[31:0]tick=0;
wire signed[15:0]yaw,pitch,roll;wire calibrated,pv;integer captured=0;
quaternion_pose #(.HORIZONTAL_HEADING(1),.CLK_HZ(200000)) d(.clk(clk),.rst_n(rst),.sensor_restarted(1'b0),.online(1'b1),.calibrate(cal),.quat_valid(sv),.quat_sequence(8'd0),.quat_timestamp_ticks(tick),.quat_timestamp_valid(1'b1),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(2'd2),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0),.calibrated(calibrated),.pose_valid(pv),.yaw(yaw),.pitch(pitch),.roll(roll));
always @(posedge clk)if(pv)captured=captured+1;
task sample;begin @(negedge clk);sv=1;tick=tick+50;@(negedge clk);sv=0;repeat(998)@(negedge clk);end endtask
task expect_yaw;input integer expected;begin repeat(3)sample();if($signed(yaw)<expected-3 || $signed(yaw)>expected+3)$fatal(1,"horizontal heading got%0d expected%0d",$signed(yaw),expected);end endtask
initial begin
qx=-2626;qy=2344;qz=15904;qw=1764;repeat(5)@(negedge clk);rst=1;cal=1;sample();cal=0;repeat(55)sample();
if(!calibrated)$fatal(1,"calibration failed");expect_yaw(0);
qx=2994;qy=-1852;qz=-15969;qw=1024;expect_yaw(320);
qx=3237;qy=-3071;qz=15639;qw=1986;expect_yaw(0);
qx=-3110;qy=3174;qz=13814;qw=7608;expect_yaw(-720);
qx=-qx;qy=-qy;qz=-qz;qw=-qw;expect_yaw(-720);
cal=1;sample();cal=0;repeat(55)sample();expect_yaw(0);
$display("TB_PASS Y-forward gravity-frame heading:tilted center,wrap170/-170,tilt independence,left45,quaternion sign,recenter");$finish;end
endmodule
