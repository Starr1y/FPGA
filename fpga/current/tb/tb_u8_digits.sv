`timescale 1ns/1ps
module tb_u8_digits;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;wire[7:0]r,g,b;wire hs,vs,de,req;integer n,pos,expected;
 duo04_panel d(clk,rst_n,1088'b0,1'b0,r,g,b,hs,vs,de,req);
 initial begin #1;
  for(n=0;n<256;n=n+1)for(pos=0;pos<5;pos=pos+1)begin
   case(pos)0:expected=(n/10000)%10;1:expected=(n/1000)%10;2:expected=(n/100)%10;3:expected=(n/10)%10;default:expected=n%10;endcase
   if(d.decimal_digit(n,pos)!==expected[3:0])$fatal(1,"U8 BCD mismatch");
  end
  $display("TB_PASS1280 U8 decimal glyph cases; full counters remain separate16-bit cache");$finish;
 end
endmodule
