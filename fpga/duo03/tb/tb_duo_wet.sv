module tb_duo_wet;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,status_update=0;reg[799:0]status=0;
 wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 duo_panel dut(.*);integer expected,actual;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(integer wet=0;wet<256;wet++)begin
   @(negedge clk);status[787:780]=wet;status_update=1;@(negedge clk);status_update=0;
   repeat(20)@(negedge clk);expected=wet*100/256;
   actual=dut.wet_bcd[15:12]*10+dut.wet_bcd[11:8];
   if(dut.wet_busy || dut.wet_bcd[15:12]>9 || dut.wet_bcd[11:8]>9 || actual!=expected)$fatal(1,"wet percent %0d expected%0d got%0d",wet,expected,actual);
  end
  $display("TB_PASS all256 wet percentages vs independent integer reference, bounded sequential formatter");$finish;
 end
endmodule
