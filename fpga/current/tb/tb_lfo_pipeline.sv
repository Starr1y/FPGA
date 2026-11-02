`timescale 1ns/1ps
module tb_lfo_pipeline;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,tick=0;
 reg[63:0]rates=0;reg[15:0]depth=0;wire[39:0]a,b;integer f,c,checks=0;
 performance_vibrato d(clk,rst_n,tick,rates,depth,a);
 performance_vibrato_reference ref_lfo(clk,rst_n,tick,rates,depth,b);
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(f=0;f<200;f=f+1)begin
   @(negedge clk);tick=1;rates={$random,$random};depth=f%4==0 ? 0 : $random;
   @(negedge clk);tick=0;
   for(c=0;c<100;c=c+1)begin @(negedge clk);
    // Audio's state25 cannot consume before these pipeline stages settle.
    if(c>=3)begin if(a!==b)$fatal(1,"settled vibrato differs");checks=checks+1;end
    if(depth==0&&a!={20'd65536,20'd65536})$fatal(1,"disabled LFO not unity");
   end
  end
  $display("TB_PASS LFO pipeline stable sample-consumption equality%0d checks, both hands and unity disable",checks);$finish;
 end
endmodule
