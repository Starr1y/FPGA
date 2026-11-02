`timescale 1ns/1ps
module tb_bold_font;
reg clk=0;always #5 clk=~clk;
reg rst_n=0;wire[7:0]r,g,b;wire hs,vs,de,req;
duo04_panel d(.clk(clk),.rst_n(rst_n),.status(1088'd0),.status_update(1'b0),.red(r),.green(g),.blue(b),.hsync(hs),.vsync(vs),.de(de),.frame_request(req));
integer i;reg[15:0]expected;
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 for(i=0;i<4096;i=i+1)begin
  force d.glyph=i/16;force d.row1=i%16;
  expected=d.font_rom[i]|(d.font_rom[i]>>1);
  @(posedge clk);#1;if(d.bits!==expected)$fatal(1,"bold glyph %d",i);
  @(negedge clk);
 end
 release d.glyph;release d.row1;
 $display("TB_PASS all4096font rows preserve original strokes and add only right-neighbor stroke");$finish;
end
endmodule
