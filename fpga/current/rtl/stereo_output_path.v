// Stereo PCM -> shared-control independent-channel FX -> mute ramp -> DAC PCM.
// All logic uses clk with sample enables. Mode changes drain wet to zero first.
module stereo_output_path #(parameter FX_ADDR_BITS=14,MAKEUP_SHIFT=0)(
 input clk,rst_n,input in_valid,input signed[15:0]in_left,in_right,
 input muted,input[8:0]test_gain,output input_accepted,input[1:0]requested_mode,input[7:0]requested_wet,input[1:0]clear_history,
 output reg signed[15:0]pcm_left,pcm_right,output reg pcm_valid,
 output[1:0]active_mode,output[7:0]actual_wet,output[8:0]master_gain,
 output amplifier_off,output[31:0]fx_drops,fx_clips);
 reg[1:0]mode_q;reg[7:0]wet_q;reg[8:0]gain;
 reg[1:0]mode_clear;
 wire ready,fx_valid;wire signed[15:0]fx_left,fx_right;
 assign input_accepted=in_valid && ready;
 assign active_mode=mode_q;assign actual_wet=wet_q;assign master_gain=gain;
 // Only gate actual digital silence; never apply a threshold to quiet music.
 reg[9:0]quiet_samples;
 // Keep the analogue amplifier stable across notes and tails. Explicit stop
 // still ramps the digital gain down before disabling it.
 assign amplifier_off=gain==0;
 wire[7:0]target_wet=requested_mode==0 ? 8'd0 : requested_wet;
 // 100ms delay, 12ms chorus +/-96 samples, 80ms four-tap reverb at 48kHz.
 wire[13:0]delay_samples=mode_q==1 ? 14'd4800 : mode_q==2 ? 14'd576 : 14'd3840;
 wire[7:0]feedback=mode_q==1 ? 8'd96 : 8'd80;
 wire[31:0]core_drops,limiter_drops;wire limited_valid;wire signed[15:0]limited_left,limited_right;
 assign fx_drops=core_drops+limiter_drops;
 stereo_fx #(.ADDR_BITS(FX_ADDR_BITS)) effects(
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_ready(ready),.in_left(in_left),.in_right(in_right),
  .mode(mode_q),.wet(wet_q),.feedback(feedback),.chorus_depth(8'd96),.delay_samples(delay_samples),
  .clear_history(clear_history|mode_clear),.out_valid(fx_valid),.out_left(fx_left),.out_right(fx_right),
  .dropped_samples(core_drops),.clipped_samples(fx_clips));
 generate if(MAKEUP_SHIFT!=0)begin:makeup
  stereo_makeup_limiter #(.SHIFT(MAKEUP_SHIFT)) limiter(.clk(clk),.rst_n(rst_n),.in_valid(fx_valid),.in_left(fx_left),.in_right(fx_right),
   .out_valid(limited_valid),.out_left(limited_left),.out_right(limited_right),.dropped(limiter_drops));
 end else begin:unity
  assign limited_valid=fx_valid;assign limited_left=fx_left;assign limited_right=fx_right;assign limiter_drops=0;
 end endgenerate
 // Separate multiply and rounding. Combining the sign-dependent bias with
 // the multiplier triggers a DSP27 post-adder mapper failure in Gowin 1.9.12.
 reg signed[25:0]scaled_left,scaled_right;reg scaled_valid;
 wire round_left=scaled_left[7] && (!scaled_left[25] || |scaled_left[6:0]);
 wire round_right=scaled_right[7] && (!scaled_right[25] || |scaled_right[6:0]);
 wire signed[15:0]rounded_left=scaled_left[23:8]+{15'b0,round_left};
 wire signed[15:0]rounded_right=scaled_right[23:8]+{15'b0,round_right};
 always @(posedge clk)begin
  if(!rst_n)begin mode_q<=0;wet_q<=0;gain<=0;mode_clear<=0;pcm_left<=0;pcm_right<=0;pcm_valid<=0;quiet_samples<=960;scaled_left<=0;scaled_right<=0;scaled_valid<=0;end
  else begin
   mode_clear<=0;pcm_valid<=0;scaled_valid<=limited_valid;
   if(in_valid && ready)begin
    if(requested_mode!=mode_q)begin
     if(wet_q!=0)wet_q<=wet_q-1'b1;
     else begin mode_q<=requested_mode;mode_clear<=3;end
    end else if(wet_q<target_wet)wet_q<=wet_q+1'b1;
    else if(wet_q>target_wet)wet_q<=wet_q-1'b1;
   end
   if(limited_valid)begin
    scaled_left<=limited_left*$signed({1'b0,gain});scaled_right<=limited_right*$signed({1'b0,gain});
    if(gain>(muted ? 9'd0 : test_gain))gain<=gain-1'b1;
    else if(!muted && gain<test_gain)gain<=gain+1'b1;
   end
   if(scaled_valid)begin
    pcm_left<=rounded_left;pcm_right<=rounded_right;pcm_valid<=1;
    if(rounded_left==0 && rounded_right==0)begin if(quiet_samples<960)quiet_samples<=quiet_samples+1'b1;end
    else quiet_samples<=0;
   end
  end
 end
endmodule
