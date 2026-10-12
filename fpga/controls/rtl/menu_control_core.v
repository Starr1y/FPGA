// Raw mechanical inputs -> filtered semantic events -> registered parameters.
// A portable integration boundary, not a board pin map or a complete UI.
module menu_control_core(input clk,rst_n,enabled,
 input encoder_a,encoder_b,encoder_button_n,pedal_n,input[1:0]wrist_button_n,imu_enabled,
 output focus,editing,visible,chord_mode,muted,output[3:0]page,presets,release_ids,profiles,
 output[1:0]effect_mode,calibrate,output[7:0]effect_wet,chorus_depth,feedback,
 output[13:0]delay_samples,output[3:0]button_ready,output[15:0]invalid_transitions);
 wire encoder_step,encoder_direction,encoder_short,encoder_long,pedal_toggle;
 wire[1:0]wrist_short,wrist_long;
 performance_controls inputs_filter(.clk(clk),.rst_n(rst_n),.enabled(enabled),.encoder_a(encoder_a),.encoder_b(encoder_b),
  .encoder_button_n(encoder_button_n),.pedal_n(pedal_n),.wrist_button_n(wrist_button_n),
  .encoder_step(encoder_step),.encoder_direction(encoder_direction),.encoder_short(encoder_short),.encoder_long(encoder_long),
  .pedal_toggle(pedal_toggle),.wrist_short(wrist_short),.wrist_long(wrist_long),.button_ready(button_ready),.invalid_transitions(invalid_transitions));
 instrument_menu parameters(.clk(clk),.rst_n(rst_n),.enabled(enabled),.encoder_step(encoder_step),.encoder_direction(encoder_direction),
  .encoder_short(encoder_short),.encoder_long(encoder_long),.pedal_toggle(pedal_toggle),.wrist_short(wrist_short),.wrist_long(wrist_long),.imu_enabled(imu_enabled),
  .focus(focus),.editing(editing),.visible(visible),.page(page),.presets(presets),.release_ids(release_ids),.profiles(profiles),.chord_mode(chord_mode),.muted(muted),
  .effect_mode(effect_mode),.calibrate(calibrate),.effect_wet(effect_wet),.chorus_depth(chorus_depth),.feedback(feedback),.delay_samples(delay_samples));
endmodule
