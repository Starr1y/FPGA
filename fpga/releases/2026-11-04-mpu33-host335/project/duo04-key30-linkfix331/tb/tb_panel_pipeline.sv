`timescale 1ns/1ps
module tb_panel_pipeline;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,status_update=0;reg[1087:0]status=0;
 wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 duo04_panel dut(.*);
 integer n,count=0,rows=0,line=0;reg expect_de,expect_hs,expect_vs;
 initial begin
  repeat(8)@(negedge clk);rst_n=1;
  repeat(8)@(negedge clk);
  for(n=0;n<1312*624;n=n+1)begin
   @(posedge clk);
   expect_de=dut.raw_x2<1024 && dut.raw_y2<600;
   expect_hs=!(dut.raw_x2>=1072 && dut.raw_x2<1168);
   expect_vs=!(dut.raw_y2>=603 && dut.raw_y2<613);
   @(negedge clk);
   if(dut.x!=(dut.raw_x0*5/8) || dut.y!=(dut.raw_y0*4/5))$fatal(1,"coordinate accumulator mismatch");
   if(de!==expect_de || hsync!==expect_hs || vsync!==expect_vs)$fatal(1,"sync pipeline mismatch");
   if(de)begin count++;if($isunknown({red,green,blue}))$fatal(1,"unknown pixel");end
  end
  if(count!=1024*600)$fatal(1,"active sample count %0d",count);
  $display("TB_PASS full 1312x624 raster, exact coordinate scaling, 614400 active pixels, sync aligned");$finish;
 end
endmodule
