// One canonical menu owns synth/effect parameters. Semantic pulses come from
// performance_controls; this core does not assign physical pins or render HDMI.
// Uses two_hand_i2c_core's existing queue/epoch/release handshake directly;
// do not insert a second event queue between the sensor core and this consumer.
module menu_performance_core #(parameter VOICES=32,CLK_HZ=50000000,
 parameter HOLD_TICKS=(CLK_HZ/1000)*60,VB=$clog2(VOICES))(
 input clk,rst_n,controls_enabled,input[1:0]imu_enabled,
 input encoder_step,encoder_direction,encoder_short,encoder_long,pedal_toggle,
 input[1:0]wrist_short,wrist_long,
 input event_valid,output event_ready,input[63:0]event_data,
 input[1:0]release_pending,output[1:0]release_ack,input[63:0]epochs,
 input[1:0]clear_history,
 input[31:0]bend_cents,vibrato_cents,input[15:0]brightness,
 output[1:0]calibrate,output[3:0]profiles,output[63:0]control_status,
 output[VOICES-1:0]owned,gates,active_voices,output[VOICES*7-1:0]notes,
 output[VOICES*16-1:0]envelopes,voice_samples,
 output signed[15:0]pcm_left,pcm_right,output pcm_valid,
 output bck,ws,dout,amplifier_off,
 output[31:0]underflows,invalid_events,stolen_notes,stereo_clips,fx_drops,fx_clips,
 output[15:0]max_render_cycles,output[1:0]active_effect,
 output[7:0]actual_wet,active_feedback,active_depth,output[13:0]active_delay,
 output transitioning,output[8:0]master_gain);
 wire focus,editing,visible,chord_mode,muted;wire[3:0]page,presets,release_ids;
 wire[1:0]effect_mode;wire[7:0]effect_wet,chorus_depth,feedback;wire[13:0]delay_samples;
 instrument_menu parameters(.clk(clk),.rst_n(rst_n),.enabled(controls_enabled),
  .encoder_step(encoder_step),.encoder_direction(encoder_direction),.encoder_short(encoder_short),.encoder_long(encoder_long),
  .pedal_toggle(pedal_toggle),.wrist_short(wrist_short),.wrist_long(wrist_long),.imu_enabled(imu_enabled),
  .focus(focus),.editing(editing),.visible(visible),.page(page),.presets(presets),.release_ids(release_ids),.profiles(profiles),
  .chord_mode(chord_mode),.muted(muted),.effect_mode(effect_mode),.calibrate(calibrate),
  .effect_wet(effect_wet),.chorus_depth(chorus_depth),.feedback(feedback),.delay_samples(delay_samples));
 assign control_status={3'b0,visible,chorus_depth,feedback,delay_samples,effect_wet,effect_mode,
  profiles,release_ids,presets,chord_mode,muted,focus,editing,page};
 reg[1:0]previous_enabled;
 always @(posedge clk)begin if(!rst_n)previous_enabled<=0;else previous_enabled<=imu_enabled;end
 // Queue cancellation stays with the sensor producer. Wet history is invalidated
 // on the same lifecycle boundaries, without cutting the natural dry tail.
 wire[1:0]clear_now=clear_history|calibrate|(previous_enabled & ~imu_enabled);
 wire sample_tick,sample_valid;wire[79:0]samples;wire[31:0]mono_clips;
 wire signed[15:0]dry_left,dry_right;
 two_hand_synth #(.VOICES(VOICES),.CLK_HZ(CLK_HZ),.HOLD_TICKS(HOLD_TICKS)) instrument(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
  .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.chord_mode(chord_mode),
  .preset_ids(presets),.release_ids(release_ids),.bend_cents(bend_cents),.vibrato_cents(vibrato_cents),.brightness(brightness),
  .samples(samples),.sample_valid(sample_valid),.clips(mono_clips),.stereo_left(dry_left),.stereo_right(dry_right),.stereo_clips(stereo_clips),
  .underflows(underflows),.owned(owned),.gates(gates),.active_voices(active_voices),.notes(notes),.envelopes(envelopes),.voice_samples(voice_samples),
  .invalid_events(invalid_events),.stolen_notes(stolen_notes),.max_render_cycles(max_render_cycles),
  .monitor_voice({VB{1'b0}}),.monitor_frequency(),.monitor_envelope(),.monitor_stage());
 parameter_stereo_output output_path(.clk(clk),.rst_n(rst_n),.in_valid(sample_valid),.in_left(dry_left),.in_right(dry_right),
  .muted(muted),.requested_mode(effect_mode),.requested_wet(effect_wet),.requested_feedback(feedback),.requested_depth(chorus_depth),
  .requested_delay(delay_samples),.clear_history(clear_now),.pcm_left(pcm_left),.pcm_right(pcm_right),.pcm_valid(pcm_valid),
  .active_mode(active_effect),.actual_wet(actual_wet),.active_feedback(active_feedback),.active_depth(active_depth),.active_delay(active_delay),
  .transitioning(transitioning),.master_gain(master_gain),.amplifier_off(amplifier_off),.fx_drops(fx_drops),.fx_clips(fx_clips));
 pt8211_output #(.CLK_HZ(CLK_HZ)) dac(.clk(clk),.rst_n(rst_n),.pcm_left(pcm_left),.pcm_right(pcm_right),
  .bck(bck),.ws(ws),.dout(dout),.sample_tick(sample_tick));
endmodule
