`timescale 1ns/1ps
// Primitive stubs are used only to elaborate the video wrapper reset logic.
module OSER10(output Q,input D0,D1,D2,D3,D4,D5,D6,D7,D8,D9,PCLK,FCLK,RESET);assign Q=0;endmodule
module ELVDS_OBUF(input I,output O,OB);assign O=I;assign OB=~I;endmodule
module tb_pixel_reset_bridge;
 reg core=0,pixel=0;always #10 core=~core;always #10.2040816 pixel=~pixel;
 reg rst_n=0,lock=0;wire cp,cn;wire[2:0]dp,dn;integer phase,k;
 video_duo_hdmi d(.clk50(core),.rst_n(rst_n),.pixel_clk_in(pixel),.serial_clk_in(pixel),.pll_lock_in(lock),
 .menu_status(288'b0),.performance_status(800'b0),.tmds_clk_p(cp),.tmds_clk_n(cn),.tmds_d_p(dp),.tmds_d_n(dn));
 task three_edges(input expected);
 begin for(k=0;k<3;k=k+1)begin @(posedge pixel);#0.001;
  if(k==2&&d.pixel_reset_n!==expected)$fatal(1,"three-stage reset transfer");
 end end endtask
 initial begin
  #1;if(d.pixel_reset_n!==0)$fatal(1,"initial reset");lock=1;
  repeat(5)@(negedge pixel);
  for(phase=0;phase<=40;phase=phase+1)begin
   @(negedge core);#(phase*0.5+0.001);rst_n=1;three_edges(1);
   @(negedge core);#(phase*0.5+0.001);rst_n=0;three_edges(0);
   rst_n=1;three_edges(1);#1;lock=0;#0.001;
   if(d.pixel_reset_n!==0)$fatal(1,"PLL loss must assert asynchronously");
   #3;lock=1;three_edges(1);rst_n=0;three_edges(0);
  end
  $display("TB_PASS41 reset phases, core reset assertion/release3pixel clocks, immediate PLL-loss assertion");$finish;
 end
 initial begin #100000;$fatal(1,"reset timeout");end
endmodule
