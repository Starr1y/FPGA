// Visible event feedback independent of audio voices, envelopes and DAC data.
// Each accepted zone hit is held for 300 ms; another hit restarts only that zone.
module imu_ui_feedback #(parameter CLK_HZ=50000000,parameter HOLD_MS=300,parameter ZONES=7,parameter ZONE_BITS=$clog2(ZONES))(
 input clk,input rst_n,input clear,input hit_valid,input [ZONE_BITS-1:0] hit_zone,
 output [ZONES-1:0] hit_mask
);
 localparam HOLD_TICKS=(CLK_HZ/1000)*HOLD_MS;
 localparam COUNTER_BITS=$clog2(HOLD_TICKS+1);
 reg [COUNTER_BITS-1:0] remaining[0:ZONES-1];
 genvar g;
 generate for(g=0;g<ZONES;g=g+1)begin: zones
  assign hit_mask[g]=remaining[g]!=0;
  always @(posedge clk)begin
   if(!rst_n || clear)remaining[g]<=0;
   else if(hit_valid && hit_zone==g)remaining[g]<=HOLD_TICKS;
   else if(remaining[g]!=0)remaining[g]<=remaining[g]-1'b1;
  end
 end endgenerate
endmodule
