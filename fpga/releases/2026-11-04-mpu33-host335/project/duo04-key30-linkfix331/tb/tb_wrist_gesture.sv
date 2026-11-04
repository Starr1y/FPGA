`timescale 1ns/1ps
module tb_wrist_gesture;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,clear=0,enabled=1,invert=0,button_n=1,pose_valid=0,playable=1,hit=0;
 reg signed[15:0]pitch=0;reg[3:0]zone=0,hit_zone=0;reg zone_valid=1;
 wire pressed,fresh;wire[1:0]octave,snapshot;wire signed[15:0]bend;wire[15:0]serial;
 wrist_gesture #(.CLK_HZ(1000)) d(clk,rst_n,clear,enabled,invert,button_n,pose_valid,playable,pitch,zone,zone_valid,hit,hit_zone,2'b0,2'b0,1'b0,pressed,octave,fresh,snapshot,bend,serial,);
 task frames(input integer count,input integer angle);integer i;begin
  for(i=0;i<count;i=i+1)begin @(negedge clk);pitch=angle*16;pose_valid=(i%5)==0;@(posedge clk);#1;end
  @(negedge clk);pose_valid=0;
 end endtask
 initial begin
  #12;rst_n=1;frames(100,0);
  if(!fresh || octave!=0 || snapshot!=0)$fatal(1,"initial C4/fresh");
  frames(160,-42);if(octave!=2 || snapshot!=2)$fatal(1,"C2");
  frames(160,-22);if(octave!=3)$fatal(1,"C3");
  frames(160,0);if(octave!=0)$fatal(1,"C4");
  frames(160,35);if(octave!=1)$fatal(1,"C5");
  frames(160,0);@(negedge clk);hit=1;@(negedge clk);hit=0;
  button_n=0;frames(25,0);if(!pressed || bend>3 || bend< -3)$fatal(1,"press jump %d",bend);
  frames(150,25);if(bend<970 || bend>1010 || octave!=0)$fatal(1,"pitch or octave lock %d %d",bend,octave);
  // 60ms passage across a whole octave; no retrigger serial change.
  zone=6;frames(100,25);if(bend<2070 || bend>2110 || serial!=1)$fatal(1,"zone glide %d",bend);
  zone_valid=0;frames(50,25);if(bend<2070)$fatal(1,"out of zone must retain target");
  button_n=1;frames(25,25);if(pressed)$fatal(1,"release");
  button_n=0;playable=0;frames(25,25);if(pressed || fresh || bend!=0)$fatal(1,"loss cancellation");
  playable=1;button_n=0;frames(100,0);if(pressed)$fatal(1,"held after loss must release");
  button_n=1;frames(25,0);button_n=0;frames(25,0);if(!pressed)$fatal(1,"rearm");
  $display("TB_PASS four octaves/history/hold/pitch/zone/cancel");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
