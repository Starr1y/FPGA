// Independent DAC calibration source. 256-sample amplitude ramp (~5.33ms).
// Valid and samples are pipelined together; no voice envelope or FX involved.
module sine_calibrator(input clk,rst_n,sample_tick,enable,input[31:0]frequency,
 input[15:0]amplitude,input[1:0]channels,
 output active,output reg valid,output reg signed[15:0]left,right);
 reg[31:0]phase;reg[8:0]ramp,held_ramp;reg[2:0]pipeline;reg[1:0]held_channels,channels_q;
 wire signed[15:0]sine;sine_lut lut(.addr(phase[31:22]),.value(sine));
 reg signed[32:0]product;reg signed[25:0]faded;
 wire signed[15:0]scaled=product[30:15]+{15'b0,(product[14] && (!product[32] || |product[13:0]))};
 wire signed[15:0]sample=faded[23:8]+{15'b0,(faded[7] && (!faded[25] || |faded[6:0]))};
 assign active=enable || ramp!=0 || held_ramp!=0 || faded!=0 || left!=0 || right!=0;
 always @(posedge clk)begin
  if(!rst_n)begin phase<=0;ramp<=0;held_ramp<=0;pipeline<=0;valid<=0;left<=0;right<=0;product<=0;faded<=0;held_channels<=0;channels_q<=0;end
  else begin
   pipeline<={pipeline[1:0],sample_tick};valid<=pipeline[2];
   if(sample_tick)begin
    phase<=phase+frequency;
    if(enable && ramp<256)ramp<=ramp+1'b1;else if(!enable && ramp!=0)ramp<=ramp-1'b1;
    product<=sine*$signed({1'b0,amplitude});held_ramp<=ramp;held_channels<=channels;
   end
   if(pipeline[0])begin faded<=scaled*$signed({1'b0,held_ramp});channels_q<=held_channels;end
   if(pipeline[1])begin left<=channels_q[0] ? sample : 16'sd0;right<=channels_q[1] ? sample : 16'sd0;end
  end
 end
endmodule
