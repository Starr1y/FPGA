// Digital event-to-PCM integration; no physical DAC/HDMI/pin assignment.
module two_hand_synth #(parameter VOICES=32,CLK_HZ=50000000,ENABLE_EXPRESSION=0,
 parameter HOLD_TICKS=(CLK_HZ/1000)*60,VB=$clog2(VOICES))(
 input clk,rst_n,sample_tick,input event_valid,output event_ready,input[63:0]event_data,
 input[1:0]release_pending,output[1:0]release_ack,input[63:0]epochs,
 input chord_mode,input[5:0]preset_ids,input[3:0]release_ids,
 input[31:0]hold_ticks_left,hold_ticks_right,input[1:0]piano_hold,input[31:0]piano_coefficients,
 input[47:0]glide_coefficients,input[39:0]vibrato_ratios,
 input[31:0]bend_cents,vibrato_cents,input[15:0]brightness,
 output[79:0]samples,output sample_valid,output[31:0]clips,underflows,
 output signed[15:0]stereo_left,stereo_right,output[31:0]stereo_clips,
 output[VOICES-1:0]owned,gates,active_voices,output[VOICES*7-1:0]notes,
 output[VOICES*16-1:0]envelopes,voice_samples,
 output[31:0]invalid_events,stolen_notes,output[15:0]max_render_cycles,
 input[VB-1:0]monitor_voice,output[31:0]monitor_frequency,output[15:0]monitor_envelope,output[1:0]monitor_stage,
 output committed,output[7:0]committed_id,output committed_hand
);
 wire config_valid,config_ready;wire[127:0]config_data;wire[VOICES*8-1:0]voice_brightness;
 dual_voice_scheduler #(.VOICES(VOICES),.CLK_HZ(CLK_HZ),.HOLD_TICKS(HOLD_TICKS)) scheduler(
  .clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
  .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.chord_mode(chord_mode),
  .preset_ids(preset_ids),.release_ids(release_ids),.hold_ticks_left(hold_ticks_left),.hold_ticks_right(hold_ticks_right),.mono_glide(ENABLE_EXPRESSION ? {|glide_coefficients[47:24],|glide_coefficients[23:0]} : 2'b0),.bend_cents(bend_cents),.vibrato_cents(vibrato_cents),.brightness(brightness),
  .envelopes(envelopes),.config_valid(config_valid),.config_ready(config_ready),.config_data(config_data),
  .voice_brightness(voice_brightness),.owned(owned),.gates(gates),.notes(notes),.invalid_events(invalid_events),.stolen_notes(stolen_notes),.committed(committed),.committed_id(committed_id),.committed_hand(committed_hand));
 wire[63:0]first_envelopes;wire[15:0]last_render_cycles;
 dual_audio_core #(.VOICES(VOICES),.MASTER_SHIFT(VOICES==32 ? 4 : 1),.ENABLE_EXPRESSION(ENABLE_EXPRESSION)) audio(
  .glide_coefficients(glide_coefficients),.vibrato_ratios(vibrato_ratios),.piano_hold(piano_hold),.piano_coefficients(piano_coefficients),
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.config_valid(config_valid && config_ready),.config_data(config_data),.config_ready(config_ready),
  .samples(samples),.sample_valid(sample_valid),.clips(clips),.stereo_left(stereo_left),.stereo_right(stereo_right),.stereo_clips(stereo_clips),.local_brightness(voice_brightness),.envelopes(first_envelopes),
  .all_envelopes(envelopes),.voice_samples(voice_samples),.active_voices(active_voices),.underflows(underflows),
  .last_render_cycles(last_render_cycles),.max_render_cycles(max_render_cycles),
  .monitor_voice(monitor_voice),.monitor_frequency(monitor_frequency),.monitor_envelope(monitor_envelope),.monitor_stage(monitor_stage));
endmodule
