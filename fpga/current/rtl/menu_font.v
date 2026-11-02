// TangLab Menu Bitmap; WenKai Mono 20px / 24x24; SIL OFL 1.1.
module menu_font(input clk,enabled,input[6:0]glyph,input[4:0]row,output reg[23:0]bits);
reg[23:0]rom[0:2111] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/menu_font.hex",rom);
wire[11:0]g={5'b0,glyph};
wire[11:0]address=(g<<4)+(g<<3)+(row<24 ? row : 0);
always @(posedge clk)if(enabled)bits<=rom[address];
endmodule
