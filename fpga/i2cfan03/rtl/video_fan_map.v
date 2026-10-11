// Compact geometry only: 3 profiles x 160 scanlines x 13 inclusive spans.
module video_fan_map(input clk,input rst_n,input [1:0] profile,input [9:0] x,y,
 input enabled,output reg [11:0] zones,output reg boundary);
 reg [233:0] spans[0:479] /* synthesis syn_ramstyle="block_ram" */;
 initial $readmemh("rtl/fan_spans.hex",spans);
 wire [8:0] row=y-237;
 wire valid=enabled && x>=168 && x<472 && y>=237 && y<397;
 wire [8:0] address=(profile==1 ? 9'd160 : profile==2 ? 9'd320 : 9'd0)+row;
 reg [233:0] line;reg [8:0] col;reg valid_p;
 always @(posedge clk)begin
  line<=spans[valid ? address : 0];col<=x-168;valid_p<=rst_n && valid;
 end
 integer i;reg hole;
 always @* begin
  zones=0;boundary=0;hole=col>=line[216+:9] && col<=line[225+:9];
  if(valid_p && !hole)for(i=0;i<12;i=i+1)begin
   if(col>=line[i*18+:9] && col<=line[i*18+9+:9])begin
    zones[i]=1;
    if(col<=line[i*18+:9]+1 || col+1>=line[i*18+9+:9])boundary=1;
   end
  end
 end
endmodule
