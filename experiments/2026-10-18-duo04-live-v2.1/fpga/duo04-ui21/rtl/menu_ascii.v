module menu_ascii(input clk,enabled,input[7:0]ch,input[4:0]row,output reg[12:0]bits);
reg[3:0]glyph;
always @*begin glyph=0;case(ch)
8'd32:glyph=4'd0;
8'd48:glyph=4'd1;
8'd49:glyph=4'd2;
8'd50:glyph=4'd3;
8'd51:glyph=4'd4;
8'd52:glyph=4'd5;
8'd53:glyph=4'd6;
8'd54:glyph=4'd7;
8'd55:glyph=4'd8;
8'd56:glyph=4'd9;
8'd57:glyph=4'd10;
8'd46:glyph=4'd11;
8'd37:glyph=4'd12;
8'd45:glyph=4'd13;
default:glyph=0;endcase end
reg[12:0]rom[0:335] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/menu_ascii.hex",rom);
wire[8:0]g={5'b0,glyph};
wire[8:0]address=(g<<4)+(g<<3)+(row<24 ? row : 0);
always @(posedge clk)if(enabled)bits<=rom[address];
endmodule
