`timescale 1ns/1ps
// Behavioral clock/differential/serializer stubs test pixel/TMDS logic only.
// They do not prove PLL lock, pin electrical quality or a real HDMI sink.
module video_pll_125(output reg lock=0,output reg clkout0=0,output reg clkout1=0,input clkin);
 always #4 clkout0=!clkout0;
 always @(posedge clkin)clkout1<=!clkout1;
 initial begin #200;lock=1;end
endmodule
module ELVDS_OBUF(input I,output O,OB);assign O=I;assign OB=!I;endmodule
module OSER10(input D0,D1,D2,D3,D4,D5,D6,D7,D8,D9,PCLK,FCLK,RESET,output reg Q=0);
 reg [9:0] held=0;integer index=0;
 always @(posedge PCLK)begin held<={D9,D8,D7,D6,D5,D4,D3,D2,D1,D0};index=0;end
 always @(posedge FCLK or negedge FCLK)begin
  if(RESET)begin Q<=0;index=0;end
  else if(index<10)begin Q<=held[index];index=index+1;end
 end
endmodule
module tb_video_hdmi;
 reg clk50=0;always #10 clk50=!clk50;
 reg rst_n=0,sample_valid=0;reg [79:0] samples=0;
 reg [1023:0] performance_status=0;
 wire tmds_clk_p,tmds_clk_n;wire [2:0] tmds_d_p,tmds_d_n;
 video_hdmi dut(.*);
 reg [23:0] expected_rgb[0:3];reg expected_de[0:3];reg [1:0] expected_ctrl[0:3];
 reg [23:0] incoming;reg incoming_de;reg [1:0] incoming_ctrl;
 integer age=0,active_checked=0,blank_checked=0,i;
 function [7:0] decode;
  input [9:0] word;reg [7:0] transition;integer bit_number;
  begin
   transition=word[9] ? ~word[7:0] : word[7:0];decode[0]=transition[0];
   for(bit_number=1;bit_number<8;bit_number++)
    decode[bit_number]=word[8] ? transition[bit_number]^transition[bit_number-1] :
                                        !(transition[bit_number]^transition[bit_number-1]);
  end
 endfunction
 function [9:0] control_word;
  input [1:0] value;
  begin case(value)0:control_word=10'b1101010100;1:control_word=10'b0010101011;
   2:control_word=10'b0101010100;3:control_word=10'b1010101011;endcase end
 endfunction
 always @(posedge dut.pixel_clk)begin
  if(!dut.pixel_reset_n)age=0;
  else begin
   incoming={dut.red,dut.green,dut.blue};incoming_de=dut.de;incoming_ctrl={dut.vsync,dut.hsync};
   for(i=3;i>0;i--)begin expected_rgb[i]=expected_rgb[i-1];expected_de[i]=expected_de[i-1];expected_ctrl[i]=expected_ctrl[i-1];end
   expected_rgb[0]=incoming;expected_de[0]=incoming_de;expected_ctrl[0]=incoming_ctrl;
   age++;#1;
   if(dut.rgb_pixel!==incoming || dut.rgb_de!==incoming_de || {dut.rgb_vsync,dut.rgb_hsync}!==incoming_ctrl)
    $fatal(1,"RGB/blanking pipeline did not capture coherent pixel");
   if(age>4)begin
    if(expected_de[3])begin
     if({decode(dut.tmds_word[2]),decode(dut.tmds_word[1]),decode(dut.tmds_word[0])}!==expected_rgb[3])
      $fatal(1,"decoded TMDS RGB differs from pixel/controls pipeline");
     active_checked++;
    end else begin
     if(dut.tmds_word[0]!==control_word(expected_ctrl[3]) || dut.tmds_word[1]!==control_word(0) || dut.tmds_word[2]!==control_word(0))
      $fatal(1,"TMDS blank/sync shifted independently of RGB");
     blank_checked++;
    end
   end
  end
 end
 initial begin
  performance_status[389]=1;performance_status[390]=1;performance_status[351:320]=32'hffffffff;
  performance_status[766:761]=32;performance_status[728:473]={32{8'd255}};
  performance_status[768]=1;performance_status[905:890]=450;performance_status[825:810]=8;
  repeat(10)@(negedge clk50);rst_n=1;
  wait(dut.pixel_reset_n);wait(dut.panel.y==524 && dut.panel.x==799);repeat(6)@(negedge dut.pixel_clk);
  if(active_checked<300000 || blank_checked<100000)$fatal(1,"incomplete active/blank video raster");
  if(dut.panel.ui_status[766:761]!=32 || !dut.panel.ui_status[389])$fatal(1,"actual wrapper did not transfer 32-Voice status");
  if(dut.panel.ui_status[905:890]!=450 || !dut.panel.ui_status[768] || dut.panel.ui_status[825:810]!=8)
   $fatal(1,"actual wrapper did not transfer upper delay status");
  $display("TB_PASS real video wrapper: coherent RGB/sync pipeline, independent TMDS decode over active/blank raster and 1024-bit frame status");$finish;
 end
 initial begin #20000000;$fatal(1,"HDMI pipeline watchdog");end
endmodule
