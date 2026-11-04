module duo_fan(input clk,rst_n,input[1:0]profile,input[8:0]col,row,input enabled,
 output reg[11:0]zones,output reg boundary);
reg[233:0]rom[0:419] /* synthesis syn_ramstyle="block_ram" */;
initial $readmemh("rtl/ui23_spans.hex",rom);
wire valid=enabled && col<280 && row<140;
wire[8:0]address=(profile==1 ? 9'd140 : profile==2 ? 9'd280 : 9'd0)+row;
reg[233:0]line;reg[8:0]col_p;reg valid_p;integer i;reg hole;
always @(posedge clk)begin line<=rom[valid ? address : 0];col_p<=col;valid_p<=rst_n && valid;end
always @* begin zones=0;boundary=0;hole=col_p>=line[216+:9] && col_p<=line[225+:9];
if(valid_p && !hole)for(i=0;i<12;i=i+1)if(col_p>=line[i*18+:9] && col_p<=line[i*18+9+:9])begin
zones[i]=1;if(col_p<=line[i*18+:9]+1 || col_p+1>=line[i*18+9+:9])boundary=1;end
end
endmodule
