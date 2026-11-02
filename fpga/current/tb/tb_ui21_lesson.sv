`timescale 1ns/1ps
module tb_ui21_lesson;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,enabled=1,restart=0,clear_feedback=0;reg[1:0]song=0;
 reg hit=0,hand=0;reg[6:0]note=60;reg[3:0]zone=0;
 wire[4:0]position;wire[15:0]correct,wrong,event_serial;wire target_hand,finished,last_correct,feedback_hand;wire[6:0]target_note;wire[3:0]target_zone,feedback_zone;wire[1:0]feedback;
 duo04_lesson #(.CLK_HZ(1000)) dut(.*);
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task strike(input h,input[6:0]n,input[3:0]z);begin @(negedge clk);hand=h;note=n;zone=z;hit=1;@(negedge clk);hit=0;end endtask
 integer i;
 initial begin
  cycles(3);rst_n=1;cycles(2);
  strike(1,60,0);if(position!=0 || wrong!=1 || feedback!=2 || feedback_hand!=1)$fatal(1,"wrong hand advance");
  cycles(181);if(feedback!=0)$fatal(1,"wrong interval");
  strike(0,60,0);if(position!=0 || correct!=1 || feedback!=1)$fatal(1,"correct should hold old target");
  strike(0,62,1);if(correct!=1 || wrong!=1)$fatal(1,"double hit during success scored");
  cycles(100);enabled=0;cycles(300);if(position!=0 || feedback!=1)$fatal(1,"pause lost accepted success");
  enabled=1;cycles(150);if(position!=1 || feedback!=0 || target_note!=62)$fatal(1,"resume did not advance once");
  strike(0,62,1);cycles(250);if(position!=2 || correct!=2)$fatal(1,"next hit");
  for(i=2;i<16;i=i+1)begin strike(target_hand,target_note,target_zone);cycles(250);end
  if(!finished || correct!=16)$fatal(1,"finish");strike(0,60,0);if(correct!=16)$fatal(1,"finish auto repeat");
  restart=1;song=2;cycles(1);restart=0;cycles(1);if(position!=0 || correct!=0)$fatal(1,"restart");
  strike(0,60,0);cycles(250);if(!target_hand || target_note!=62)$fatal(1,"alternating hand");
  strike(1,62,1);clear_feedback=1;cycles(1);clear_feedback=0;if(position!=2 || feedback!=0)$fatal(1,"stop drops accepted step");
  $display("TB_PASS lesson 250/180ms, wrong hand, repeated hit, pause/resume, completion/restart");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
