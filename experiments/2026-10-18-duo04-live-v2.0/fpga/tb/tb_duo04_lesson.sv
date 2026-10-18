`timescale 1ns/1ps
module tb_duo04_lesson;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enabled=1,restart=0,hit=0,hand=0;reg[6:0]note=60;reg[1:0]song=2;
 wire[4:0]position;wire[15:0]correct,wrong;wire target_hand,finished,last_correct;wire[6:0]target_note;wire[3:0]zone;
 duo04_lesson dut(.*,.target_zone(zone));
 task strike(input bit h,input[6:0]n);begin @(negedge clk);hand=h;note=n;hit=1;@(negedge clk);hit=0;end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  strike(1,60);if(position!=0 || wrong!=1)$fatal(1,"wrong hand advanced");
  strike(0,61);if(position!=0 || wrong!=2)$fatal(1,"wrong note advanced");
  for(integer i=0;i<16;i++)begin strike(target_hand,target_note);if(position!=i+1)$fatal(1,"correct note stalled");end
  if(!finished || correct!=16)$fatal(1,"completion");
  @(negedge clk);restart=1;@(negedge clk);restart=0;
  if(position!=0 || wrong!=0 || correct!=0)$fatal(1,"restart");
  $display("TB_PASS lesson hand/note checks, wrong/no advance, complete/restart");$finish;
 end
endmodule
