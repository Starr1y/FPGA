// Tang Mega NEO 138K board adapter. Manual permission is not supply supervision.
// Two separate 0x4A buses, no GPIO drives high into the IMUs.
module top_duo01(input clk,reset_key,input key0_n,key1_n,key2_n,
 inout[1:0]imu_scl,imu_sda,imu_rst_n,input[1:0]imu_int_n,
 output hp_bck,hp_ws,hp_din,pa_en,
 output tmds_clk_p_0,tmds_clk_n_0,output[2:0]tmds_d_p_0,tmds_d_n_0);
 reg[19:0]boot=0;reg[1:0]reset_sync=0;
 always @(posedge clk)begin if(!boot[19])boot<=boot+1'b1;reset_sync<={reset_sync[0],reset_key};end
 wire rst_n=boot[19] && !reset_sync[1];
 wire focus,diagnostic,muted,chord_mode,combo_active;
 wire[1:0]enabled,calibrate,force_reset,express;wire[3:0]profiles,presets;
 duo_keys keys(.clk(clk),.rst_n(rst_n),.key0_n(key0_n),.key1_n(key1_n),.key2_n(key2_n),
  .focus(focus),.diagnostic(diagnostic),.muted(muted),.chord_mode(chord_mode),
  .enabled(enabled),.calibrate(calibrate),.force_reset(force_reset),.profiles(profiles),.presets(presets),.express(express),.combo_active(combo_active));
 wire[1:0]scl_low,sda_low,reset_low,online;
 genvar h;generate for(h=0;h<2;h=h+1)begin:pad
  assign imu_scl[h]=scl_low[h] ? 1'b0 : 1'bz;
  assign imu_sda[h]=sda_low[h] ? 1'b0 : 1'bz;
  assign imu_rst_n[h]=reset_low[h] ? 1'b0 : 1'bz;
 end endgenerate
 wire[511:0]status;wire[95:0]rates;wire[63:0]overruns,drops,cancelled;
 wire[79:0]samples;wire sample_valid,sample_tick;wire[31:0]clips,underflows,invalid,stolen;
 wire[31:0]owned,gates,active;wire[223:0]notes;wire[511:0]envelopes,voice_samples;wire[15:0]max_render;
 two_hand_instrument_core #(.VOICES(32),.CLK_HZ(50000000),.HALF_DIV(100)) instrument(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.enabled(enabled),.force_reset(force_reset),.calibrate(calibrate),.express(express),.mirror(2'b00),
  .layout_profile(profiles),.scl_in(imu_scl),.sda_in(imu_sda),.int_n(imu_int_n),.scl_low(scl_low),.sda_low(sda_low),.reset_low(reset_low),.online(online),
  .chord_mode(chord_mode),.preset_ids(presets),.release_ids(4'b0101),.status(status),.report_rates(rates),.processing_overruns(overruns),.event_drops(drops),.cancelled_events(cancelled),
  .samples(samples),.sample_valid(sample_valid),.clips(clips),.underflows(underflows),.invalid_events(invalid),.stolen_notes(stolen),
  .owned(owned),.gates(gates),.active_voices(active),.notes(notes),.envelopes(envelopes),.voice_samples(voice_samples),.max_render_cycles(max_render),
  .monitor_voice(5'b0),.monitor_frequency(),.monitor_envelope(),.monitor_stage());
 // 256-sample gain ramp; amplifier stays off until the first nonzero gain.
 reg[8:0]gain;reg signed[24:0]scaled;reg[15:0]pcm;
 always @(posedge clk)begin
  if(!rst_n)begin gain<=0;scaled<=0;pcm<=0;end
  else if(sample_valid)begin
   if(muted && gain!=0)gain<=gain-1'b1;else if(!muted && gain<256)gain<=gain+1'b1;
   scaled=$signed(samples[79:64])*$signed({1'b0,gain});pcm<=scaled>>>8;
  end
 end
 assign pa_en=gain==0;
 pt8211_output dac(.clk(clk),.rst_n(rst_n),.pcm_left(pcm),.pcm_right(pcm),.bck(hp_bck),.ws(hp_ws),.dout(hp_din),.sample_tick(sample_tick));
 reg[7:0]active_count;integer i;
 always @*begin active_count=0;for(i=0;i<32;i=i+1)active_count=active_count+active[i];end
 wire[767:0]display_status={overruns[31:0],rates,8'b0,drops[31:0],underflows,clips,active_count,
  1'b0,combo_active,chord_mode,muted,diagnostic,focus,enabled,presets,profiles,status};
 video_duo_hdmi display(.clk50(clk),.rst_n(rst_n),.performance_status(display_status),
  .tmds_clk_p(tmds_clk_p_0),.tmds_clk_n(tmds_clk_n_0),.tmds_d_p(tmds_d_p_0),.tmds_d_n(tmds_d_n_0));
endmodule
