`timescale 1ns/1ps
module tb_stereo_fx;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,in_valid=0;wire in_ready;
 reg signed[15:0]in_left=0,in_right=0;reg[1:0]mode=0;
 reg[7:0]wet=255,feedback=0,chorus_depth=0;reg[13:0]delay_samples=3;
 reg[1:0]clear_history=0;wire out_valid;wire signed[15:0]out_left,out_right;
 wire[31:0]dropped_samples,clipped_samples;
 stereo_fx #(.ADDR_BITS(5),.LFO_INCREMENT(2097152)) dut(.*);
 task reset;begin
  @(negedge clk);rst_n=0;in_valid=0;clear_history=0;repeat(3)@(negedge clk);rst_n=1;
 end endtask
 task sample(input integer l,r);
  integer waits;begin
   wait(in_ready);@(negedge clk);in_left=l;in_right=r;in_valid=1;
   @(negedge clk);in_valid=0;waits=0;
   while(!out_valid)begin @(negedge clk);waits++;if(waits>8)$fatal(1,"unbounded processing");end
   if(waits!=7)$fatal(1,"pipeline latency %0d",waits);
   if((^out_left===1'bx)||(^out_right===1'bx))$fatal(1,"unwritten RAM leaked");
  end
 endtask
 integer i;
 initial begin
  reset();mode=0;feedback=255;chorus_depth=255;delay_samples=0;
  for(i=0;i<40;i++)begin sample(i*801-16000,16000-i*811);
   if(out_left!==in_left || out_right!==in_right)$fatal(1,"bypass changed PCM");end
  reset();mode=1;feedback=128;chorus_depth=0;delay_samples=3;
  for(i=0;i<13;i++)begin sample(i==0 ? 10000 : 0,0);
   if(out_right!=0)$fatal(1,"delay crossed channels");
   case(i)0:if(out_left!=39)$fatal(1,"dry weight");
    3:if(out_left!=9960)$fatal(1,"first echo %0d",out_left);
    6:if(out_left!=4980)$fatal(1,"feedback echo %0d",out_left);
    9:if(out_left!=2490)$fatal(1,"feedback decay %0d",out_left);
    default:if(out_left!=0 && i!=12)$fatal(1,"wrong delay distance");endcase
  end
  reset();mode=3;feedback=0;delay_samples=8;
  for(i=0;i<12;i++)begin sample(i==0 ? 10000 : 0,i==0 ? -10000 : 0);
   if(i==4 || i==6 || i==7 || i==8)begin
    if(out_left!=2490 || out_right!=-2491)$fatal(1,"reverb tap %0d: %0d %0d",i,out_left,out_right);
   end else if(i!=0 && (out_left!=0 || out_right!=0))$fatal(1,"unexpected reverb tap");
  end
  reset();mode=2;delay_samples=8;chorus_depth=4;
  for(i=0;i<90;i++)begin sample(1000,2000);
   if(i>31 && (out_left!=1000 || out_right!=2000))$fatal(1,"chorus constant signal / ring wrap");end
  if(dut.primary_left==dut.primary_right)$fatal(1,"chorus stereo phase absent");
  reset();mode=1;delay_samples=3;feedback=0;sample(10000,20000);
  @(negedge clk);clear_history=1;@(negedge clk);clear_history=0;
  sample(0,0);sample(0,0);sample(0,0);
  if(out_left!=0 || out_right!=19921)$fatal(1,"per-channel history clear %0d %0d",out_left,out_right);
  // Clear an echo already read during the in-flight transaction.
  reset();mode=1;delay_samples=1;feedback=0;sample(10000,20000);
  wait(in_ready);@(negedge clk);in_left=0;in_right=0;in_valid=1;
  @(negedge clk);in_valid=0;wait(dut.state==5);
  @(negedge clk);clear_history=1;@(negedge clk);clear_history=0;
  wait(out_valid);#1;
  if(out_left!=0 || out_right!=19921)$fatal(1,"in-flight clear leaked old wet sample");
  reset();mode=1;delay_samples=1;feedback=255;
  for(i=0;i<40;i++)sample(32767,-32768);
  if(clipped_samples==0 || out_left<0 || out_right>=0)$fatal(1,"feedback saturation");
  wait(in_ready);@(negedge clk);in_valid=1;in_left=7;in_right=-9;
  repeat(3)@(negedge clk);in_valid=0;wait(out_valid);
  if(dropped_samples!=2)$fatal(1,"busy drop accounting %0d",dropped_samples);
  $display("TB_PASS stereo FX: exact bypass, unwritten memory guard, independent delay/feedback, four reverb taps, stereo chorus/ring wrap, per-channel/in-flight clear, clipping and busy accounting; 50MHz eight-clock transaction");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
