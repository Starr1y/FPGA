// Real parameter source -> held frame snapshot -> menu pixels.
// Clocks supplied by the enclosing video adapter. No PLL, TMDS or board pins.
module menu_display_core(input core_clk,pixel_clk,core_rst_n,pixel_rst_n,controls_enabled,
 input encoder_a,encoder_b,encoder_button_n,pedal_n,input[1:0]wrist_button_n,imu_enabled,
 output focus,editing,visible,chord_mode,muted,output[3:0]page,presets,release_ids,profiles,
 output[1:0]effect_mode,calibrate,output[7:0]effect_wet,chorus_depth,feedback,
 output[13:0]delay_samples,output[3:0]button_ready,output[15:0]invalid_transitions,
 output[7:0]red,green,blue,output hsync,vsync,de,output visible_pixel);
 menu_control_core controls(.clk(core_clk),.rst_n(core_rst_n),.enabled(controls_enabled),
  .encoder_a(encoder_a),.encoder_b(encoder_b),.encoder_button_n(encoder_button_n),.pedal_n(pedal_n),
  .wrist_button_n(wrist_button_n),.imu_enabled(imu_enabled),.focus(focus),.editing(editing),.visible(visible),
  .chord_mode(chord_mode),.muted(muted),.page(page),.presets(presets),.release_ids(release_ids),.profiles(profiles),
  .effect_mode(effect_mode),.calibrate(calibrate),.effect_wet(effect_wet),.chorus_depth(chorus_depth),.feedback(feedback),
  .delay_samples(delay_samples),.button_ready(button_ready),.invalid_transitions(invalid_transitions));
 wire[63:0]core_status={3'b0,visible,chorus_depth,feedback,delay_samples,effect_wet,effect_mode,
  profiles,release_ids,presets,chord_mode,muted,focus,editing,page};
 wire[63:0]pixel_status;wire pixel_status_valid,frame_request;
 video_status_cdc #(.WIDTH(64)) snapshot(.core_clk(core_clk),.core_reset_n(core_rst_n),.core_status(core_status),
  .pixel_clk(pixel_clk),.pixel_reset_n(pixel_rst_n),.frame_request(frame_request),.pixel_status(pixel_status),.pixel_status_valid(pixel_status_valid));
 // Use the same held snapshot as the panel, not an independently synchronized
 // visibility bit. The caller can mux pixels only at these frame boundaries.
 reg show_menu;
 always @(posedge pixel_clk)begin
  if(!pixel_rst_n)show_menu<=0;else if(pixel_status_valid)show_menu<=pixel_status[60];
 end
 assign visible_pixel=show_menu;
 menu_panel panel(.clk(pixel_clk),.rst_n(pixel_rst_n),.status(pixel_status),.status_update(pixel_status_valid),
  .red(red),.green(green),.blue(blue),.hsync(hsync),.vsync(vsync),.de(de),.frame_request(frame_request));
endmodule
