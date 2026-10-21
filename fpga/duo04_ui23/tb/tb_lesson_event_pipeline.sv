`timescale 1ns/1ps
module tb_lesson_event_pipeline;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,flush=0,accepted=0;
 reg[63:0]event_data=0,epochs={32'd9,32'd7};
 wire hit,hand;wire[6:0]note;wire[3:0]zone;
 lesson_event_pipeline dut(.*);
 task tick;@(posedge clk);#1;endtask
 task drive(input a,input h,input[3:0]z,input[1:0]kind,input[31:0]epoch);
 begin @(negedge clk);accepted=a;event_data=0;
 event_data[63:32]=epoch;event_data[31:30]=kind;
 event_data[29]=h;event_data[28:25]=z;end endtask
 initial begin
  tick();rst_n=1;
  drive(1,0,0,0,7);tick();if(hit)$fatal(1,"observation bypassed first stage");
  drive(1,1,4,0,9);tick();
  if(!hit || hand || note!=60 || zone!=0)$fatal(1,"first note metadata lost");
  drive(0,0,6,0,7);tick();
  if(!hit || !hand || note!=67 || zone!=4)$fatal(1,"consecutive hand/note pair crossed");
  tick();if(hit)$fatal(1,"unaccepted/backpressured event scored");
  drive(1,0,0,1,7);tick();drive(0,0,0,0,7);tick();if(hit)$fatal(1,"gain-only event scored");
  drive(1,0,15,0,7);tick();drive(0,0,0,0,7);tick();if(hit)$fatal(1,"invalid zone scored");
  drive(1,0,0,0,7);tick();@(negedge clk);accepted=0;epochs[31:0]=8;tick();
  if(hit)$fatal(1,"canceled epoch scored");
  drive(1,0,0,0,8);tick();@(negedge clk);accepted=0;flush=1;#1;
  if(hit)$fatal(1,"STOP failed immediate feedback suppression");tick();
  @(negedge clk);flush=0;tick();tick();if(hit)$fatal(1,"STOP replayed delayed hit");
  drive(1,0,0,0,8);tick();drive(0,0,0,0,8);tick();if(!hit)$fatal(1,"pipeline failed restart");
  @(negedge clk);flush=1;#1;if(hit)$fatal(1,"already valid hit escaped STOP");tick();
  $display("TB_PASS lesson observer: paired back-to-back hands, accepted-only hits, gain/invalid rejection, epoch cancellation, STOP flush/restart");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
