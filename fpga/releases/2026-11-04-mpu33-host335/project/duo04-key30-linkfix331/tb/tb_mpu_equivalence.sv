`timescale 1ns/1ps
`include "tb/mpu6050_fusion_reference.v"
module tb_mpu_equivalence;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,start=0;reg signed[15:0]ax_raw=0,ay_raw=0,az_raw=4096,gx_raw=0,gy_raw=0,gz_raw=0;
 reg[15:0]dt_us=5000;
 wire busy,done,ready,busy_ref,done_ref,ready_ref;
 wire[31:0]overruns,overruns_ref;
 wire signed[15:0]qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz,qx_ref,qy_ref,qz_ref,qw_ref,ax_ref,ay_ref,az_ref,gx_ref,gy_ref,gz_ref,gravity_x_ref,gravity_y_ref,gravity_z_ref,lx_ref,ly_ref,lz_ref;
mpu6050_fusion dut(.clk(clk),.rst_n(rst_n),.start(start),.ax_raw(ax_raw),.ay_raw(ay_raw),.az_raw(az_raw),.gx_raw(gx_raw),.gy_raw(gy_raw),.gz_raw(gz_raw),.dt_us(dt_us),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(lz),.busy(busy),.done(done),.ready(ready),.overruns(overruns));
mpu6050_fusion_reference reference(.clk(clk),.rst_n(rst_n),.start(start),.ax_raw(ax_raw),.ay_raw(ay_raw),.az_raw(az_raw),.gx_raw(gx_raw),.gy_raw(gy_raw),.gz_raw(gz_raw),.dt_us(dt_us),.qx(qx_ref),.qy(qy_ref),.qz(qz_ref),.qw(qw_ref),.ax(ax_ref),.ay(ay_ref),.az(az_ref),.gx(gx_ref),.gy(gy_ref),.gz(gz_ref),.gravity_x(gravity_x_ref),.gravity_y(gravity_y_ref),.gravity_z(gravity_z_ref),.lx(lx_ref),.ly(ly_ref),.lz(lz_ref),.busy(busy_ref),.done(done_ref),.ready(ready_ref),.overruns(overruns_ref));
 integer total=0,max_cycles=0,seed=28461,k,n;reg[31:0]random_word;
 reg seen_new,seen_old;
 task sample;
  begin
   @(negedge clk);start=1;@(negedge clk);start=0;n=0;seen_new=0;seen_old=0;
   while(!seen_new || !seen_old)begin
    @(negedge clk);n=n+1;if(done)seen_new=1;if(done_ref)seen_old=1;
    if(n>1000)$fatal(1,"completion timeout");
   end
   if(n>max_cycles)max_cycles=n;
   if({qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz,ready,overruns} !== {qx_ref,qy_ref,qz_ref,qw_ref,ax_ref,ay_ref,az_ref,gx_ref,gy_ref,gz_ref,gravity_x_ref,gravity_y_ref,gravity_z_ref,lx_ref,ly_ref,lz_ref,ready_ref,overruns_ref})$fatal(1,"bit exact mismatch sample=%d",total);
   total=total+1;
  end
 endtask
 task reset_filter;
  begin @(negedge clk);rst_n=0;repeat(4)@(negedge clk);rst_n=1;end
 endtask
 initial begin
  reset_filter();for(k=0;k<620;k=k+1)sample();
  for(k=0;k<2000;k=k+1)begin
   random_word=$random(seed);gx_raw=$signed(random_word[15:0])>>>3;
   random_word=$random(seed);gy_raw=$signed(random_word[15:0])>>>3;
   random_word=$random(seed);gz_raw=$signed(random_word[15:0])>>>3;
   random_word=$random(seed);ax_raw=$signed(random_word[15:0])>>>4;
   random_word=$random(seed);ay_raw=$signed(random_word[15:0])>>>4;
   random_word=$random(seed);az_raw=4096+($signed(random_word[15:0])>>>4);
   dt_us=(k%5==0)?500:(k%5==1)?15000:5000;
   sample();
  end
  gx_raw=0;gy_raw=0;gz_raw=0;ax_raw=0;ay_raw=2896;az_raw=2896;
  reset_filter();for(k=0;k<650;k=k+1)sample();
  ay_raw=0;az_raw=-4096;reset_filter();for(k=0;k<650;k=k+1)sample();
  // Interrupt an in-flight computation; neither stale result may escape reset.
  @(negedge clk);start=1;@(negedge clk);start=0;repeat(20)@(negedge clk);
  reset_filter();sample();
  $display("TB_PASS bit-exact reports=%0d max_cycles=%0d seed=28461",total,max_cycles);$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
