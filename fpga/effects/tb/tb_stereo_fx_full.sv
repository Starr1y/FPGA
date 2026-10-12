`timescale 1ns/1ps
// Default 16384-sample RAMs, maximum delay and two complete pointer wraps.
module tb_stereo_fx_full;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,in_valid=0;wire in_ready;
 reg signed[15:0]in_left=0,in_right=0;reg[1:0]mode=1;
 reg[7:0]wet=255,feedback=0,chorus_depth=0;reg[13:0]delay_samples=16383;
 reg[1:0]clear_history=0;wire out_valid;wire signed[15:0]out_left,out_right;
 wire[31:0]dropped_samples,clipped_samples;
 stereo_fx dut(.*);
 task sample(input integer l,r);
  begin
   wait(in_ready);@(negedge clk);in_left=l;in_right=r;in_valid=1;
   @(negedge clk);in_valid=0;wait(out_valid);@(negedge clk);
   if((^out_left===1'bx)||(^out_right===1'bx))$fatal(1,"unknown RAM sample");
  end
 endtask
 integer n,echo_l,echo_r,expected_l,expected_r;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(n=0;n<33000;n++)begin
   if(n==16000)begin @(negedge clk);clear_history=1;@(negedge clk);clear_history=0;end
   sample(n%256,-(n%512));
   echo_l=n>=32383 ? (n-16383)%256 : 0;
   echo_r=n>=16383 ? -((n-16383)%512) : 0;
   expected_l=((n%256)+echo_l*255)>>>8;expected_r=(-(n%512)+echo_r*255)>>>8;
   if(out_left!==expected_l || out_right!==expected_r)$fatal(1,"full ring sample %0d: %0d/%0d expected %0d/%0d",n,out_left,out_right,expected_l,expected_r);
  end
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;sample(500,-1000);
  if(out_left!=1 || out_right!=-4)$fatal(1,"reset leaked previous RAM contents");
  if(dropped_samples || clipped_samples)$fatal(1,"full ring counters");
  $display("TB_PASS default 16384-sample stereo RAMs: 33000 samples, max delay, two pointer wraps, independent history clear and reset over populated RAM");$finish;
 end
 initial begin #10000000;$fatal(1,"watchdog");end
endmodule
