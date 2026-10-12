// Stereo PCM -> shared-control independent-channel FX -> mute ramp -> DAC PCM.
// All logic uses clk with sample enables. Mode changes drain wet to zero first.
module stereo_output_path #(parameter FX_ADDR_BITS=14)(
 input clk,rst_n,input in_valid,input signed[15:0]in_left,in_right,
 input muted,input[1:0]requested_mode,input[7:0]requested_wet,input[1:0]clear_history,
 output reg signed[15:0]pcm_left,pcm_right,output reg pcm_valid,
 output[1:0]active_mode,output[7:0]actual_wet,output[8:0]master_gain,
 output amplifier_off,output[31:0]fx_drops,fx_clips);
 reg[1:0]mode_q;reg[7:0]wet_q;reg[8:0]gain;
 reg[1:0]mode_clear;
 wire ready,fx_valid;wire signed[15:0]fx_left,fx_right;
 assign active_mode=mode_q;assign actual_wet=wet_q;assign master_gain=gain;
 assign amplifier_off=gain==0;
 wire[7:0]target_wet=requested_mode==0 ? 8'd0 : requested_wet;
 // 100ms delay, 12ms chorus +/-96 samples, 80ms four-tap reverb at 48kHz.
 wire[13:0]delay_samples=mode_q==1 ? 14'd4800 : mode_q==2 ? 14'd576 : 14'd3840;
 wire[7:0]feedback=mode_q==1 ? 8'd96 : 8'd80;
 stereo_fx #(.ADDR_BITS(FX_ADDR_BITS)) effects(
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_ready(ready),.in_left(in_left),.in_right(in_right),
  .mode(mode_q),.wet(wet_q),.feedback(feedback),.chorus_depth(8'd96),.delay_samples(delay_samples),
  .clear_history(clear_history|mode_clear),.out_valid(fx_valid),.out_left(fx_left),.out_right(fx_right),
  .dropped_samples(fx_drops),.clipped_samples(fx_clips));
 wire signed[25:0]scaled_left=fx_left*$signed({1'b0,gain});
 wire signed[25:0]scaled_right=fx_right*$signed({1'b0,gain});
 always @(posedge clk)begin
  if(!rst_n)begin mode_q<=0;wet_q<=0;gain<=0;mode_clear<=0;pcm_left<=0;pcm_right<=0;pcm_valid<=0;end
  else begin
   mode_clear<=0;pcm_valid<=0;
   if(in_valid && ready)begin
    if(requested_mode!=mode_q)begin
     if(wet_q!=0)wet_q<=wet_q-1'b1;
     else begin mode_q<=requested_mode;mode_clear<=3;end
    end else if(wet_q<target_wet)wet_q<=wet_q+1'b1;
    else if(wet_q>target_wet)wet_q<=wet_q-1'b1;
   end
   if(fx_valid)begin
    if(muted && gain!=0)gain<=gain-1'b1;
    else if(!muted && gain<256)gain<=gain+1'b1;
    pcm_left<=scaled_left>>>8;pcm_right<=scaled_right>>>8;pcm_valid<=1;
   end
  end
 end
endmodule
