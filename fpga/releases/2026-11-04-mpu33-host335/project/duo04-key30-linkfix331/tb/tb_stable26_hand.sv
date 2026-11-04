`timescale 1ns/1ps
// Decoder-boundary injection: real hand, snapshot and trigger datapath, no I2C hardware claim.
module tb_stable26_hand;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,pv=0,lv=0;reg[7:0]seq=0;reg[31:0]ts=0;
 reg signed[15:0]z=0;reg[1:0]oct=3;reg online=1;wire note_on;wire[767:0]diag;wire[255:0]status;
 wire[1:0]hit_octave;wire[3:0]hit_zone;integer notes=0;
 bno_i2c_hand #(.CLK_HZ(100000)) h(.clk(clk),.rst_n(rst_n),.enabled(1'b1),.force_reset(1'b0),.calibrate(1'b0),.express(1'b0),.mirror(1'b0),
 .snapshot_enable(1'b1),.stable_octave(oct),.layout_profile(2'd0),.scl_in(1'b1),.sda_in(1'b1),.int_n(1'b1),.note_on(note_on),.hit_octave(hit_octave),.hit_zone(hit_zone),.diagnostic(diag),.status(status));
 always @(posedge clk)if(note_on)begin
  notes=notes+1;if(hit_zone!==3 || hit_octave!==3)$fatal(1,"incoherent prehit zone/octave %d %d",hit_zone,hit_octave);
 end
 task sample(input integer zz);begin
  @(negedge clk);ts=ts+25;seq=seq+1;z=zz;lv=1;pv=seq[0];
  @(negedge clk);lv=0;pv=0;repeat(248)@(negedge clk);
 end endtask
 initial begin
  force h.report_clock=ts;force h.online=online;force h.calibrated=1;force h.calibrating=0;force h.accuracy=3;
  force h.sensor_restarted=0;force h.pose_valid=pv;force h.pose_timestamp=ts;force h.pose_timestamp_valid=1;
  force h.yaw=0;force h.pitch=0;force h.roll=0;force h.gx=0;force h.gy=0;force h.gz=0;
  force h.gyro_valid=lv;force h.linear_valid=lv;force h.linear_sequence=seq;force h.linear_timestamp=ts;force h.linear_timestamp_valid=1;force h.lz=z;
  repeat(8)@(negedge clk);rst_n=1;
  repeat(40)sample(0);oct=1;repeat(2)sample(0);sample(-900);repeat(2)sample(0);
  if(notes!=1 || status[159:128]!=1)$fatal(1,"accepted hit not delivered %d",notes);
  if(diag[599:592]!=2 || !diag[600])$fatal(1,"extension/snapshot flags");
  online=0;repeat(45)sample(0);sample(-900);if(notes!=1)$fatal(1,"offline hit");
  online=1;repeat(2)sample(0);sample(-900);if(notes!=1)$fatal(1,"recovery used invalid old history");
  $display("TB_PASS real hand trigger + paired prehit snapshot + offline/recovery guard");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
