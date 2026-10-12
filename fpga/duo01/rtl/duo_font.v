// WenKai Mono derivative; SIL OFL 1.1. See docs/reference/fonts/WenKai-OFL.txt.
module duo_font(input clk,input [6:0]glyph,input [4:0]row,output reg[23:0]bits);
reg[23:0]rom[0:1751] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/duo_font.hex",rom);
always @(posedge clk)bits<=rom[glyph*24+(row<24 ? row : 0)];
endmodule
