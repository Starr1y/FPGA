`timescale 1ns/1ps
// Normalize clock counts to keep deadline and sample/window boundary tests short.
// The pin-level path test separately uses production 50MHz timing.
module tb_calibration_quality;
 reg clk=0;always #10 clk=!clk;
 reg rst_n=0,sensor_restarted=0,online=1,calibrate=0,quat_valid=0;
 reg signed [15:0] qx=0,qy=0,qz=0,qw=16384,gx=0,gy=0,gz=0;
 reg [1:0] accuracy=0;
 wire calibrated,calibrating,pose_valid;wire signed [15:0] yaw,pitch,roll;
 wire [5:0] calibration_progress;wire [1:0] calibration_state;wire [31:0] overruns;
 quaternion_pose #(.CLK_HZ(1000),.CAL_TIMEOUT_TICKS(1000)) dut(.*);
 task request;
  begin @(negedge clk);calibrate=1;@(negedge clk);calibrate=0;end
 endtask
 task sample;
  begin @(negedge clk);quat_valid=1;@(negedge clk);quat_valid=0;repeat(8)@(negedge clk);end
 endtask
 integer n;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;request();
  repeat(55)sample();
  if(!calibrating || calibrated || calibration_progress!=0 || calibration_state!=1)
   $fatal(1,"quality0 must block calibration and report its cause");
  repeat(460)@(negedge clk);
  if(calibrating || calibrated || calibration_progress!=0 || calibration_state!=3)
   $fatal(1,"unreliable input must time out without publishing an origin");
  // A timed-out request stays failed even after quality improves.
  accuracy=3;repeat(55)sample();
  if(calibrated || calibration_state!=3)$fatal(1,"deadline must require a new KEY0 request");
  request();gx=300;sample();
  if(calibration_progress!=0 || calibration_state!=2)$fatal(1,"movement must be explained");
  gx=0;repeat(10)sample();accuracy=1;sample();
  if(calibration_progress!=0 || calibration_state!=1)$fatal(1,"quality fall must discard partial mean");
  accuracy=2;
  for(n=0;n<50;n++)begin qw=n[0] ? -16384 : 16384;sample();end
  if(!calibrated || calibrating || calibration_progress!=50 || calibration_state!=0)
   $fatal(1,"medium accuracy and 50 stable sign-aligned samples must recover");
  sample();repeat(220)@(negedge clk);
  if(yaw<-16 || yaw>16 || pitch<-16 || pitch>16 || roll<-16 || roll>16)
   $fatal(1,"recovered mean must give a zero relative pose");
  // Light tremor that the old +/-102 gyro and +/-384 component limits
  // rejected is now accepted; the final mean still uses 32 valid samples.
  qw=16384;qx=0;gx=180;request();
  repeat(10)sample();qx=512;qw=16376;repeat(10)sample();
  if(calibration_progress!=20)$fatal(1,"light tremor still restarts calibration");
  gx=600;sample();sample();
  if(calibration_progress!=20 || calibration_state!=2)$fatal(1,"transient motion must pause rather than reset");
  sample();if(calibration_progress!=0)$fatal(1,"sustained motion must discard origin candidate");
  gx=180;qx=0;qw=16384;repeat(20)sample();
  gx=600;sample();sample();gx=180;repeat(30)sample();
  if(!calibrated || calibrating || calibration_progress!=50)$fatal(1,"isolated motion must recover without starting over");
  sample();repeat(220)@(negedge clk);
  if(yaw<-16 || yaw>16 || pitch<-16 || pitch>16 || roll<-16 || roll>16)
   $fatal(1,"moving reports contaminated the origin mean");
  request();repeat(10)sample();online=0;repeat(1002)@(negedge clk);
  if(calibrating || calibrated || calibration_state!=3)$fatal(1,"offline wait must be bounded too");
  @(negedge clk);sensor_restarted=1;@(negedge clk);sensor_restarted=0;
  if(calibrating || calibrated || calibration_state!=0)$fatal(1,"sensor reset must clear calibration status");
  $display("TB_PASS quality0/movement/quality fall/deadline/no auto-origin/medium-quality recovery/sign-aligned mean/offline/reset");$finish;
 end
 initial begin #300000;$fatal(1,"calibration test watchdog");end
endmodule
