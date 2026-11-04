`timescale 1ns/1ps
// Output primitives are passive stand-ins: this bench tests reset/CDC RTL,
// not device serializer electrical behavior or PLL timing.
module OSER10(input D0,D1,D2,D3,D4,D5,D6,D7,D8,D9,PCLK,FCLK,RESET,output Q);assign Q=D0;endmodule
module ELVDS_OBUF(input I,output O,OB);assign O=I;assign OB=~I;endmodule
module tb_pixel_reset;
 reg clk50=0,pixel_clk_in=0,serial_clk_in=0;
 always #10 clk50=~clk50;always #10.204 pixel_clk_in=~pixel_clk_in;always #2.041 serial_clk_in=~serial_clk_in;
 reg rst_n=0,pll_lock_in=0;reg[287:0]menu_status=0;reg[799:0]performance_status=0;
 wire tmds_clk_p,tmds_clk_n;wire[2:0]tmds_d_p,tmds_d_n;
 video_duo_hdmi dut(.*);
 integer i;
 initial begin
  #3;pll_lock_in=1;repeat(5)@(negedge pixel_clk_in);
  if(dut.pixel_reset_n!==0)$fatal(1,"reset released without core ready");
  rst_n=1;
  for(i=1;i<=3;i++)begin @(posedge pixel_clk_in);#1;if(dut.pixel_reset_n!==(i==3))$fatal(1,"release not three pixel stages");end
  @(negedge pixel_clk_in);rst_n=0;
  repeat(3)@(posedge pixel_clk_in);#1;if(dut.pixel_reset_n!==0)$fatal(1,"core reset not synchronized");
  @(negedge pixel_clk_in);rst_n=1;repeat(3)@(posedge pixel_clk_in);#1;if(!dut.pixel_reset_n)$fatal(1,"restart failed");
  #2;pll_lock_in=0;#1;if(dut.pixel_reset_n!==0)$fatal(1,"PLL loss not async clear");
  $display("TB_PASS pixel reset three-stage release, core reset/restart, immediate PLL-loss clear; output primitives stubbed");$finish;
 end
endmodule
