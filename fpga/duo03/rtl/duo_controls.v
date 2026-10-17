// Raw onboard keys and external controls share a single parameter owner.
// KEY0+KEY1 short opens/closes the menu. In that view KEY0 confirms/returns,
// KEY1/KEY2 select or edit +/-. Other lifecycle combos retain their meanings.
module duo_controls #(
 parameter CLK_HZ=50000000,DEBOUNCE_MS=20,SHORT_MS=50,LONG_MS=1500,COMBO_MS=2000,EXPRESS_MS=300,
 parameter ENC_DEBOUNCE_MS=2,EDGES_PER_STEP=4
)(input clk,rst_n,input key0_n,key1_n,key2_n,
 input encoder_a,encoder_b,encoder_button_n,pedal_n,input[1:0]wrist_button_n,
 output focus,diagnostic,muted,chord_mode,visible,editing,
 output[1:0]enabled,calibrate,force_reset,express,effect_mode,
 output[3:0]profiles,presets,release_ids,page,output[7:0]effect_wet,chorus_depth,feedback,
 output[13:0]delay_samples,output combo_active,
 output[63:0]menu_status,output[15:0]invalid_transitions,output[3:0]button_ready);
 wire[11:0]actions;wire express_held,key1_pressed;
 duo_key_events #(.CLK_HZ(CLK_HZ),.DEBOUNCE_MS(DEBOUNCE_MS),.SHORT_MS(SHORT_MS),.LONG_MS(LONG_MS),.COMBO_MS(COMBO_MS),.EXPRESS_MS(EXPRESS_MS)) keys(
  .clk(clk),.rst_n(rst_n),.key0_n(key0_n),.key1_n(key1_n),.key2_n(key2_n),.actions(actions),
  .express_held(express_held),.key1_pressed(key1_pressed),.combo_active(combo_active));
 wire ext_step,ext_direction,ext_short,ext_long,pedal_toggle;wire[1:0]wrist_short,wrist_long;
 performance_controls #(.CLK_HZ(CLK_HZ),.ENC_DEBOUNCE_MS(ENC_DEBOUNCE_MS),.EDGES_PER_STEP(EDGES_PER_STEP),
  .BUTTON_DEBOUNCE_MS(DEBOUNCE_MS),.SHORT_MS(SHORT_MS),.LONG_MS(LONG_MS)) external_inputs(
  .clk(clk),.rst_n(rst_n),.enabled(1'b1),.encoder_a(encoder_a),.encoder_b(encoder_b),.encoder_button_n(encoder_button_n),
  .pedal_n(pedal_n),.wrist_button_n(wrist_button_n),.encoder_step(ext_step),.encoder_direction(ext_direction),
  .encoder_short(ext_short),.encoder_long(ext_long),.pedal_toggle(pedal_toggle),.wrist_short(wrist_short),.wrist_long(wrist_long),
  .button_ready(button_ready),.invalid_transitions(invalid_transitions));
 wire board_event=|actions;
 wire menu_step=board_event ? (visible && (actions[2] || actions[3])) : ext_step;
 wire menu_direction=board_event ? actions[2] : ext_direction;
 wire menu_short=board_event ? (visible && actions[0]) : ext_short;
 wire menu_long=board_event ? (visible && actions[1]) : ext_long;
 wire[11:0]main_actions=visible ? (actions & 12'hff0) : actions;
 duo_parameters parameters(.clk(clk),.rst_n(rst_n),.enabled(1'b1),.board_actions(main_actions),
  .encoder_step(menu_step),.encoder_direction(menu_direction),.encoder_short(menu_short),.encoder_long(menu_long),
  .pedal_toggle(pedal_toggle),.wrist_short(wrist_short),.wrist_long(wrist_long),
  .focus(focus),.editing(editing),.visible(visible),.diagnostic(diagnostic),.imu_enabled(enabled),.force_reset(force_reset),
  .page(page),.presets(presets),.release_ids(release_ids),.profiles(profiles),.chord_mode(chord_mode),.muted(muted),
  .effect_mode(effect_mode),.calibrate(calibrate),.effect_wet(effect_wet),.chorus_depth(chorus_depth),.feedback(feedback),.delay_samples(delay_samples));
 assign menu_status={3'b0,visible,chorus_depth,feedback,delay_samples,effect_wet,effect_mode,
  profiles,release_ids,presets,chord_mode,muted,focus,editing,page};
 reg down_q,expression_owner;
 always @(posedge clk)begin
  if(!rst_n)begin down_q<=0;expression_owner<=0;end
  else begin down_q<=key1_pressed;if(key1_pressed && !down_q)expression_owner<=focus;end
 end
 assign express=express_held && !visible && enabled[expression_owner] ? (expression_owner ? 2'b10 : 2'b01) : 0;
endmodule
