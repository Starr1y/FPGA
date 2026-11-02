`timescale 1ns/1ps
// Endpoint integration at raw-sample boundary. Does not model physical I2C.
module tb_vertical_mpu_hand;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,cal=0,button_n=1,sv=0,raw_online=1;
 reg signed[15:0]raw_z=31;reg[31:0]ticks=0,stamp=0;integer divider=0,hits=0,k;
 wire online,hit;wire[255:0]status;wire[767:0]diagnostic;
 bno_i2c_hand #(.MPU_VERTICAL_X(1),.DIRECT_MPU(1),.BUTTON_TRIGGER(1),.CLK_HZ(200000)) d(
 .clk(clk),.rst_n(rst_n),.enabled(1'b1),.force_reset(1'b0),.calibrate(cal),.express(1'b0),.mirror(1'b0),.button_n(button_n),
 .layout_profile(2'd0),.scl_in(1'b1),.sda_in(1'b1),.int_n(1'b0),.snapshot_enable(1'b0),.stable_octave(2'd0),
 .online(online),.note_on(hit),.status(status),.diagnostic(diagnostic));
 always @(posedge clk)begin
  if(divider==19)begin divider<=0;ticks<=ticks+1'b1;end else divider<=divider+1;
  if(hit)hits=hits+1;
 end
 task sample;begin
  @(negedge clk);stamp=ticks;sv=1;@(negedge clk);sv=0;repeat(998)@(negedge clk);
 end endtask
 initial begin
  force d.mpu_source.raw_online=raw_online;force d.mpu_source.raw_valid=sv;
  force d.mpu_source.raw_ax=8192;force d.mpu_source.raw_ay=0;force d.mpu_source.raw_az=0;
  force d.mpu_source.raw_gx=raw_z;force d.mpu_source.raw_gy=-13;force d.mpu_source.raw_gz=17;
  force d.mpu_source.raw_stamp=stamp;force d.report_clock=ticks;
  repeat(5)@(negedge clk);rst_n=1;
  repeat(420)sample();if(!online || status[1])$fatal(1,"bias init or origin unexpectedly already calibrated");
  cal=1;sample();cal=0;
  repeat(470)sample();if(!status[1] || !status[4] || status[21:18]!=3)$fatal(1,"origin/playable/center failed flags%h",status[31:0]);
  if($signed(status[47:32])>16 || $signed(status[47:32])< -16)$fatal(1,"origin not near zero");
  raw_z=31+1965;repeat(300)sample(); //30deg/s*1.5s=>45degrees
  raw_z=31;repeat(20)sample();
  if(status[21:18]!=5 || hits!=0)$fatal(1,"yaw selection or motion created hit zone%0d hits%0d",status[21:18],hits);
  button_n=0;repeat(8)sample();if(hits!=1)$fatal(1,"button note missing");repeat(20)sample();if(hits!=1)$fatal(1,"held button repeated");
  repeat(4000)@(negedge clk);sample();if(status[1] || status[4])$fatal(1,"timing gap did not invalidate origin");
  repeat(470)sample();if(status[1] || hits!=1)$fatal(1,"gap recovery reused origin or button");
  raw_online=0;repeat(10)sample();if(online || status[4])$fatal(1,"offline remained playable");
  raw_online=1;repeat(470)sample();if(hits!=1 || status[1])$fatal(1,"reconnect replayed button or origin");
  $display("TB_PASS vertical +X gravity / +X angular velocity endpoint:startup bias,manualcenter,zero heading,45deg selection,buttononly,hold,offline,reconnect origin invalidation");$finish;
 end
 initial begin #30000000;$fatal(1,"endpoint timeout");end
endmodule

