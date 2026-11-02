// Configurable successor to DUO02's fixed-preset output path. No board pins.
// Input requests must be coherent registers in clk's domain.
// Structural edits drain wet before atomically changing taps and clearing RAM
// validity. Latest request wins; no parameter FIFO can lag behind the menu.
module parameter_stereo_output #(parameter FX_ADDR_BITS=14)(
 input clk,rst_n,input in_valid,input signed[15:0]in_left,in_right,
 input muted,input[1:0]requested_mode,input[7:0]requested_wet,requested_feedback,requested_depth,
 input[13:0]requested_delay,input[1:0]clear_history,
 output reg signed[15:0]pcm_left,pcm_right,output reg pcm_valid,
 output[1:0]active_mode,output[7:0]actual_wet,active_feedback,active_depth,
 output[13:0]active_delay,output transitioning,output[8:0]master_gain,
 output amplifier_off,output[31:0]fx_drops,fx_clips);
 localparam MAX_DELAY=(1<<FX_ADDR_BITS)-1;
 wire[13:0]bounded_delay=requested_delay<1 ? 14'd1 : requested_delay>MAX_DELAY ? MAX_DELAY : requested_delay;
 wire[7:0]bounded_feedback=requested_mode==1 ? (requested_feedback>192 ? 8'd192 : requested_feedback) :
  requested_mode==3 ? (requested_feedback>128 ? 8'd128 : requested_feedback) : 8'd0;
 wire[7:0]target_wet=requested_mode==0 ? 8'd0 : requested_wet;
 reg[1:0]mode_q,mode_clear;
 reg[7:0]wet_q,feedback_q,depth_q;reg[13:0]delay_q;reg[8:0]gain;
 wire structural_edit=requested_mode!=mode_q || bounded_delay!=delay_q || requested_depth!=depth_q;
 assign active_mode=mode_q;assign actual_wet=wet_q;assign active_feedback=feedback_q;
 assign active_depth=depth_q;assign active_delay=delay_q;assign master_gain=gain;
 assign amplifier_off=gain==0;
 assign transitioning=structural_edit || wet_q!=target_wet || feedback_q!=bounded_feedback;
 wire ready,fx_valid;wire signed[15:0]fx_left,fx_right;
 stereo_fx #(.ADDR_BITS(FX_ADDR_BITS)) effects(
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_ready(ready),.in_left(in_left),.in_right(in_right),
  .mode(mode_q),.wet(wet_q),.feedback(feedback_q),.chorus_depth(depth_q),.delay_samples(delay_q),
  .clear_history(clear_history|mode_clear),.out_valid(fx_valid),.out_left(fx_left),.out_right(fx_right),
  .dropped_samples(fx_drops),.clipped_samples(fx_clips));
 wire signed[25:0]scaled_left=fx_left*$signed({1'b0,gain});
 wire signed[25:0]scaled_right=fx_right*$signed({1'b0,gain});
 always @(posedge clk)begin
  if(!rst_n)begin
   mode_q<=0;wet_q<=0;feedback_q<=0;depth_q<=96;delay_q<=MAX_DELAY<4800 ? MAX_DELAY : 4800;
   gain<=0;mode_clear<=0;pcm_left<=0;pcm_right<=0;pcm_valid<=0;
  end else begin
   mode_clear<=0;pcm_valid<=0;
   if(in_valid && ready)begin
    if(structural_edit)begin
     if(wet_q!=0)wet_q<=wet_q-1'b1;
     else begin
      mode_q<=requested_mode;delay_q<=bounded_delay;depth_q<=requested_depth;
      feedback_q<=0;mode_clear<=3;
     end
    end else begin
     if(wet_q<target_wet)wet_q<=wet_q+1'b1;
     else if(wet_q>target_wet)wet_q<=wet_q-1'b1;
     if(feedback_q<bounded_feedback)feedback_q<=feedback_q+1'b1;
     else if(feedback_q>bounded_feedback)feedback_q<=feedback_q-1'b1;
    end
   end
   if(fx_valid)begin
    if(muted && gain!=0)gain<=gain-1'b1;
    else if(!muted && gain<256)gain<=gain+1'b1;
    pcm_left<=scaled_left>>>8;pcm_right<=scaled_right>>>8;pcm_valid<=1;
   end
  end
 end
endmodule
