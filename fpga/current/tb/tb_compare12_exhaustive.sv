`timescale 1ns/1ps
module tb_compare12_exhaustive;
 reg[11:0]a=0,b=0;wire ge;integer i,j;
 unsigned_ge12 cmp(a,b,ge);
 initial begin
  for(i=0;i<4096;i=i+1)begin
   a=i;
   for(j=0;j<4096;j=j+1)begin b=j;#1;if(ge!==(i>=j))$fatal(1,"unsigned comparison %d %d",i,j);end
   if((i%1024)==1023)$display("COMPARE_PASS rows%0d/4096",i+1);
  end
  $display("TB_PASS exhaustive16777216 unsigned12 input pairs, zero-latency equality to mathematical >=");$finish;
 end
endmodule
