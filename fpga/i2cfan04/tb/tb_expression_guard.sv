`timescale 1ns/1ps
module tb_expression_guard;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,clear=0,enabled=1,pose_valid=0,pose_timestamp_valid=1;
 reg signed [15:0]roll=0,pitch=0;reg [7:0]pose_sequence=0;reg [31:0]pose_timestamp_ticks=0;
 wire sample_valid,stream_reset;wire signed[15:0]sample_roll,sample_pitch;wire[15:0]discontinuities;
 expression_stream_guard #(.CLK_HZ(10000)) dut(.*);
 task report(input integer seq,input reg[31:0]stamp,input integer accepted,input integer reset_expected);
 begin
  @(negedge clk);pose_sequence=seq;pose_timestamp_ticks=stamp;pose_valid=1;roll=seq;pitch=-seq;
  @(negedge clk);
  if(sample_valid!==accepted[0] || stream_reset!==reset_expected[0])$fatal(1,"admission seq=%0d stamp=%0d got sample/reset=%b/%b",seq,stamp,sample_valid,stream_reset);
  if(accepted && (sample_roll!==roll || sample_pitch!==pitch))$fatal(1,"angle not latched");
  pose_valid=0;repeat(6)@(negedge clk);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  report(254,32'hffffff9c,0,1);report(255,0,1,0);report(0,100,1,0);
  report(0,100,0,1);report(1,200,1,0); // replay does not replace the genuine sample
  report(3,400,0,1);report(4,500,1,0); // lost sequence, recover
  report(5,500,0,1);report(6,600,1,0); // zero dt
  report(7,100,0,1);report(8,200,1,0); // reversed timestamp
  report(9,295,1,0);report(10,400,1,0);report(11,506,0,1);
  pose_timestamp_valid=0;report(12,606,0,1);pose_timestamp_valid=1;
  report(13,706,0,1);report(14,806,1,0);
  repeat(510)@(negedge clk);
  if(dut.history_valid || sample_valid)$fatal(1,"silence did not drop history");
  report(15,906,0,1);report(16,1006,1,0);
  enabled=0;report(17,1106,0,1);enabled=1;
  report(18,1206,0,1);report(19,1306,1,0);
  if(discontinuities!=7)$fatal(1,"expected seven data faults got %0d",discontinuities);
  clear=1;repeat(4)@(negedge clk);clear=0;
  report(20,1406,0,1);
  if(discontinuities!=7)$fatal(1,"operator clear counted as fault");
  $display("TB_PASS sensor time vs burst arrival, sequence/timestamp wrap, duplicate/gap/zero/backward/dt boundaries/invalid/silence/enable/clear");$finish;
 end
endmodule
