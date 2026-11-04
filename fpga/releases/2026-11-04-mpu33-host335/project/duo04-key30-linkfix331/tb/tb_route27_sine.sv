`timescale 1ns/1ps
module tb_route27_sine;
 reg[9:0]addr;wire signed[15:0]actual,expected;
 sine_lut dut(.addr(addr),.value(actual));
 sine_lut_full_reference reference(.addr(addr),.value(expected));
 initial begin
  for(integer n=0;n<1024;n=n+1)begin addr=n;#10;if(actual!==expected)$fatal(1,"sine mismatch addr=%d got=%d expected=%d",n,actual,expected);end
  $display("TB_PASS all 1024 sine values bit-exact, no latency change");$finish;
 end
 initial begin #20000;$fatal(1,"timeout");end
endmodule
`include "tb/reference/sine_lut_full_reference.v"
