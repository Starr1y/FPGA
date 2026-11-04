`timescale 1ns/1ps
module tb_mpu_fusion;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,start=0;reg signed[15:0]axr=0,ayr=0,azr=4096,gxr=0,gyr=0,gzr=0;
 wire busy,done,ready;wire signed[15:0]qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz;wire[31:0]overruns;
 mpu6050_fusion dut(.clk(clk),.rst_n(rst),.start(start),.ax_raw(axr),.ay_raw(ayr),.az_raw(azr),.gx_raw(gxr),.gy_raw(gyr),.gz_raw(gzr),.dt_us(16'd5000),.*);
 task sample;
  integer n;begin @(negedge clk);start=1;@(negedge clk);start=0;n=0;
   while(!done)begin @(negedge clk);n=n+1;if(n>1000)$fatal(1,"fusion timeout");end
   if($isunknown({qx,qy,qz,qw,lz}))$fatal(1,"unknown outputs");
  end
 endtask
 task reset_filter;begin @(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;end endtask
 integer i;real angle;
 initial begin
  repeat(3)@(negedge clk);rst=1;
  for(i=0;i<620;i=i+1)sample();
  if(!ready || qw<16370 || qx>3 || qx< -3 || lz>3 || lz< -3 || az<2500 || az>2520)$fatal(1,"stationary %d %d ready%b",qw,lz,ready);
  gzr=1640;for(i=0;i<200;i=i+1)sample();
  if(qz<6850 || qz>7000 || qw<14750 || qw>14930)$fatal(1,"yaw expected50degrees qz=%d qw=%d",qz,qw);
  gzr=0;azr=2048;sample();if(lz> -1200 || lz< -1320)$fatal(1,"linear acceleration wrong %d",lz);
  azr=4096;gxr=0;ayr=0;reset_filter();for(i=0;i<620;i=i+1)sample();
  gxr=984;
  for(i=1;i<=200;i=i+1)begin angle=(30.0*i/200.0)*3.141592653589793/180.0;ayr=$rtoi(4096*$sin(angle));azr=$rtoi(4096*$cos(angle));sample();end
  if(qx<4100 || qx>4400 || qw<15720 || qw>15930)$fatal(1,"roll expected30degrees qx=%d qw=%d",qx,qw);
  gxr=0;ayr=2896;azr=2896;reset_filter();for(i=0;i<900;i=i+1)sample();
  if(qx<6100 || qx>6430 || qw<15000 || qw>15280)$fatal(1,"initial tilt convergence qx=%d qw=%d",qx,qw);
  gxr=0;ayr=0;azr=-4096;reset_filter();for(i=0;i<620;i=i+1)sample();
  if(qx<16360 || lz>4 || lz< -4)$fatal(1,"upside-down startup failed qx%d lz%d",qx,lz);
  if(overruns!=0)$fatal(1,"overruns");
  $display("TB_PASS MPU fusion static bias, yaw50, roll30, tilted startup45, linearZ, reset and bounded cycles");$finish;
 end
 initial begin #50000000;$fatal(1,"watchdog");end
endmodule
