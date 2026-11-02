`timescale 1ns/1ps
module tb_ui_decimal_cache;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0;reg[79:0]values=0;wire[99:0]digits;wire valid,busy;integer n,k,v;
 ui_decimal_cache d(.*);
 function[19:0]expected;input integer x;integer p;reg leading;reg[3:0]z;
 begin expected=0;leading=1;for(p=4;p>=0;p=p-1)begin
  case(p)4:z=(x/10000)%10;3:z=(x/1000)%10;2:z=(x/100)%10;1:z=(x/10)%10;default:z=x%10;endcase
  if(z!=0||p==0)leading=0;expected[p*4+:4]=leading?4'hf:z;
 end end endfunction
 task check(input integer x);begin
  @(negedge clk);values={16'(x^16'ha5a5),16'(x/2),16'(x^16'h5a5a),16'(65535-x),16'(x)};start=1;
  @(negedge clk);start=0;
  repeat(16)@(negedge clk);
  if(!valid||busy)$fatal(1,"conversion duration");
  for(k=0;k<5;k=k+1)begin v=values[k*16+:16];if(digits[k*20+:20]!==expected(v))$fatal(1,"BCD %d",v);end
 end endtask
 initial begin repeat(3)@(negedge clk);rst_n=1;
  for(n=0;n<=65535;n=n+127)check(n);
  check(9);check(10);check(99);check(100);check(999);check(1000);check(9999);check(10000);check(65535);
  $display("TB_PASS 5-channel16-bit decimal cache, boundaries, leading blanks and16-clock latency");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
