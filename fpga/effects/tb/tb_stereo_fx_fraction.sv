`timescale 1ns/1ps
// Independent integer reference for continuously varying fractional delay.
module tb_stereo_fx_fraction;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,in_valid=0;wire in_ready;
 reg signed[15:0]in_left=0,in_right=0;reg[1:0]mode=2;
 reg[7:0]wet=255,feedback=0,chorus_depth=5;reg[13:0]delay_samples=8;
 reg[1:0]clear_history=0;wire out_valid;wire signed[15:0]out_left,out_right;
 wire[31:0]dropped_samples,clipped_samples;
 stereo_fx #(.ADDR_BITS(5),.LFO_INCREMENT(123457)) dut(.*);
 function integer expected(input integer n,right_channel);
  integer p,t,d,f,a,b,echo,dry;
  begin
   p=(n*123457+(right_channel ? 4194304 : 0)) & 16777215;
   t=(p & 8388607)>>15;if(p & 8388608)t=255-t;
   d=((8<<7)+(t-128)*5)>>>7;
   f=((8<<7)+(t-128)*5)-d*128;
   if(d<1)begin d=1;f=0;end else if(d>=31)begin d=31;f=0;end
   a=n>=d ? (n-d)*200-12000 : 0;
   b=n>d ? (n-d-1)*200-12000 : 0;
   dry=n*200-12000;
   if(right_channel)begin a=-a*2;b=-b*2;dry=-dry*2;end
   echo=(a*(128-f)+b*f)>>>7;
   expected=(dry+echo*255)>>>8;
  end
 endfunction
 integer n;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(n=0;n<90;n++)begin
   wait(in_ready);@(negedge clk);in_left=n*200-12000;in_right=-in_left*2;in_valid=1;
   @(negedge clk);in_valid=0;wait(out_valid);@(negedge clk);
   if(out_left!==expected(n,0) || out_right!==expected(n,1))$fatal(1,"fractional chorus sample %0d: %0d/%0d expected %0d/%0d",n,out_left,out_right,expected(n,0),expected(n,1));
  end
  // Controls and PCM may change while processing; accepted sample is immutable.
  wait(in_ready);@(negedge clk);mode=0;in_left=1234;in_right=-4321;in_valid=1;
  @(negedge clk);in_valid=0;mode=3;wet=255;feedback=255;delay_samples=1;in_left=-777;in_right=888;
  wait(out_valid);#1;
  if(out_left!=1234 || out_right!=-4321)$fatal(1,"mode/PCM snapshot changed in flight");
  if(dropped_samples || clipped_samples)$fatal(1,"unexpected counters");
  $display("TB_PASS 90 signed fractional chorus samples vs independent reference, left/right LFO phase, ring wrap and accepted mode/PCM snapshot");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
