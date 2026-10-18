// Complete digital sensor -> event queue -> Voice/PCM path. Board adapters are external.
module two_hand_instrument_core #(
 parameter VOICES=32,CLK_HZ=50000000,HALF_DIV=100,
 parameter RESET_TICKS=CLK_HZ/100,BOOT_TICKS=CLK_HZ*3/4,RESET_SETUP_TICKS=CLK_HZ/100,
 parameter HOLD_TICKS=(CLK_HZ/1000)*60,VB=$clog2(VOICES)
)(input clk,rst_n,sample_tick,input[1:0]enabled,force_reset,calibrate,express,mirror,
 input[3:0]layout_profile,input[1:0]scl_in,sda_in,int_n,
 output[1:0]scl_low,sda_low,reset_low,online,
 input chord_mode,input[3:0]preset_ids,release_ids,
 output[511:0]status,output[95:0]report_rates,output[63:0]processing_overruns,event_drops,cancelled_events,
 output[79:0]samples,output sample_valid,output[31:0]clips,underflows,invalid_events,stolen_notes,
 output signed[15:0]stereo_left,stereo_right,output[31:0]stereo_clips,
 output[VOICES-1:0]owned,gates,active_voices,output[VOICES*7-1:0]notes,
 output[VOICES*16-1:0]envelopes,voice_samples,output[15:0]max_render_cycles,
 input[VB-1:0]monitor_voice,output[31:0]monitor_frequency,output[15:0]monitor_envelope,output[1:0]monitor_stage
);
 wire event_valid,event_ready;wire[63:0]event_data,epochs;wire[1:0]release_pending,release_ack;
 two_hand_i2c_core #(.CLK_HZ(CLK_HZ),.HALF_DIV(HALF_DIV),.RESET_TICKS(RESET_TICKS),.BOOT_TICKS(BOOT_TICKS),.RESET_SETUP_TICKS(RESET_SETUP_TICKS)) sensors(
  .clk(clk),.rst_n(rst_n),.enabled(enabled),.force_reset(force_reset),.calibrate(calibrate),.express(express),.mirror(mirror),
  .layout_profile(layout_profile),.scl_in(scl_in),.sda_in(sda_in),.int_n(int_n),.scl_low(scl_low),.sda_low(sda_low),.reset_low(reset_low),.online(online),
  .status(status),.report_rates(report_rates),.processing_overruns(processing_overruns),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
  .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.event_drops(event_drops),.cancelled_events(cancelled_events));
 two_hand_synth #(.VOICES(VOICES),.CLK_HZ(CLK_HZ),.HOLD_TICKS(HOLD_TICKS)) synth(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
  .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.chord_mode(chord_mode),.preset_ids(preset_ids),.release_ids(release_ids),
  .bend_cents({status[351:336],status[95:80]}),.vibrato_cents({status[367:352],status[111:96]}),.brightness({status[375:368],status[119:112]}),
  .samples(samples),.sample_valid(sample_valid),.clips(clips),.stereo_left(stereo_left),.stereo_right(stereo_right),.stereo_clips(stereo_clips),.underflows(underflows),.owned(owned),.gates(gates),.active_voices(active_voices),.notes(notes),
  .envelopes(envelopes),.voice_samples(voice_samples),.invalid_events(invalid_events),.stolen_notes(stolen_notes),.max_render_cycles(max_render_cycles),
  .monitor_voice(monitor_voice),.monitor_frequency(monitor_frequency),.monitor_envelope(monitor_envelope),.monitor_stage(monitor_stage));
endmodule
