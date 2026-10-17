// Per-Voice actual FTW selects ideal-PM depth limits, including live bend.
// Each table entry is safe through its bucket's upper frequency. Interpolate
// toward the next (lower) cap, never above the conservative current cap.
module fm_limits(input clk,input [31:0] frequency,input bell,output reg [15:0] limit);
 reg [15:0] caps[0:2047];
 wire [9:0] bucket=frequency[31:22];
 wire [9:0] next_bucket=bucket==1023 ? bucket : bucket+1'b1;
 reg [15:0] cap_a,cap_b,base;
 reg [7:0] fraction;
 reg [23:0] drop;
 initial $readmemh("rtl/fm_limits.hex",caps);
 always @(posedge clk)begin
  cap_a<=caps[{bell,bucket}];cap_b<=caps[{bell,next_bucket}];
  fraction<=frequency[21:14];
  base<=cap_a;drop<=(cap_a-cap_b)*fraction;
  // Round the subtraction up to retain the bound after fixed-point truncation.
  limit<=base-((drop+24'd255)>>8);
 end
endmodule
