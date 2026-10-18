`timescale 1ns/1ps
module tb_makeup_limiter;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,in_valid=0;reg signed[15:0]in_left=0,in_right=0;
 wire out_valid;wire signed[15:0]out_left,out_right;wire[31:0]dropped;
 stereo_makeup_limiter dut(.*);
 integer n=0;
 task sample(input integer l,r);
 integer timeout;
 begin
  @(negedge clk);in_left=l;in_right=r;in_valid=1;@(negedge clk);in_valid=0;timeout=0;
  while(!out_valid)begin @(negedge clk);timeout++;if(timeout>45)$fatal(1,"limiter throughput");end
  if(out_left>28000 || out_left< -28000 || out_right>28000 || out_right< -28000 || dropped)$fatal(1,"limiter ceiling/drop");
  if(l!=0 && r==-l && out_left!=-out_right)$fatal(1,"linked stereo asymmetry");
  @(negedge clk);n++;
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;sample(1000,-1000);
  if(out_left!=8000 || out_right!=-8000)$fatal(1,"makeup gain");
  sample(32767,-32767);if(out_left<27980)$fatal(1,"ceiling gain too quiet");
  sample(-32768,32767);sample(0,0);
  for(integer i=0;i<12000;i++)sample(1000,-1000);
  if(out_left!=8000)$fatal(1,"limiter release recovery");
  // A steady low note must not pump gain back up inside each audio period.
  for(integer i=0;i<2000;i++)begin
   sample($rtoi(6000*$sin(6.283185307179586*i/480.0)),-$rtoi(6000*$sin(6.283185307179586*i/480.0)));
   if(i>=480 && (dut.gain<38220 || dut.gain>38240))$fatal(1,"audio-rate gain pumping: %d",dut.gain);
  end
  for(integer i=-32768;i<32767;i+=137)sample(i,-i/2);
  $display("TB_PASS stereo limiter gain, signed extremes, safe ceiling, recovery and <45-clock throughput %d samples",n);$finish;
 end
endmodule
