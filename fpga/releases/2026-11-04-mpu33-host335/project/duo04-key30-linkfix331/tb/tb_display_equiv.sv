`timescale 1ns/1ps
`include "tb/reference_panel30.v"
module tb_display_equiv;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,status_update=0;reg[1087:0]status=0;
 wire[7:0]red,green,blue,r0,g0,b0;wire hsync,vsync,de,frame_request,h0,v0,d0,f0;
 duo04_panel dut(.*);
 reference_panel30 ref0(.clk(clk),.rst_n(rst_n),.status(status),.status_update(status_update),.red(r0),.green(g0),.blue(b0),.hsync(h0),.vsync(v0),.de(d0),.frame_request(f0));
 reg[26:0]delay0,delay1;integer n,page,errors=0;
 always @(posedge clk)begin delay0<={d0,h0,v0,r0,g0,b0};delay1<=delay0;end
 initial begin
  repeat(8)@(negedge clk);rst_n=1;
  for(page=0;page<4;page++)begin
   status[803:802]=page;status[810]=1;status[831:816]=1500;status[808:804]=11;status[901:896]={3'd3,3'd0};status_update=1;
   @(negedge clk);status_update=0;repeat(20)@(negedge clk);
   for(n=0;n<1312*624;n++)begin
    @(negedge clk);
    if({de,hsync,vsync,red,green,blue}!==delay1)begin
     errors++;if(errors<5)$display("diff page%0d x%0d y%0d new%h old%h",page,dut.raw_x2,dut.raw_y2,{de,hsync,vsync,red,green,blue},delay1);
    end
   end
  end
  if(errors)$fatal(1,"display equivalence mismatches %0d",errors);
  $display("TB_PASS four-page RGB, sync and blanking identical to frozen30 after two pipeline cycles");$finish;
 end
endmodule
