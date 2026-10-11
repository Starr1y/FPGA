// RETAINED_SPI_FAILURE_DIAGNOSTICS
module top #(parameter BENCH_MANUAL=0, parameter AUTONOMOUS_UART=1,parameter AUTONOMOUS_SPI=0,parameter SYNTH_VOICES=AUTONOMOUS_UART ? 32 : 4,parameter UI_ONLY=AUTONOMOUS_UART,parameter BOOT_COUNTER_BITS=20)(input clk,input reset_key,input key0_n,input key1_n,input key2_n,input pc_rx,output pc_tx,
 inout imu_data,input imu_int_n,input imu_power_good,inout imu_clk_tx,output imu_cs_n,output imu_mosi,output imu_rst_n,output imu_wake,
 output hp_bck,output hp_ws,output hp_din,output pa_en,output event_mark,output audio_mark,
 output tmds_clk_p_0,output tmds_clk_n_0,
 output [2:0] tmds_d_p_0,output [2:0] tmds_d_n_0);
 localparam CLK_HZ=50000000;
 reg [BOOT_COUNTER_BITS-1:0] boot=0;reg [1:0] reset_sync=0;
 wire rst_n=boot[BOOT_COUNTER_BITS-1] && !reset_sync[1];
 always @(posedge clk)begin reset_sync<={reset_sync[0],reset_key};if(!boot[BOOT_COUNTER_BITS-1])boot<=boot+1;end
 wire imu_host_enable,imu_drive_enable,imu_fault;
 wire [3:0] first_failure_reason,failure_reason;wire [15:0] failure_header;wire [1:0] failure_inputs;
 wire raw_imu_tx,raw_imu_cs,raw_imu_mosi,raw_imu_rst,raw_imu_wake;
 wire host_rx=imu_host_enable ? imu_data : 1'b1;
 wire host_scl=imu_host_enable ? imu_clk_tx : 1'b1;wire address_ack;
 wire host_int_n=imu_host_enable ? imu_int_n : 1'b1;
 // Legacy PC-controlled transport is retired: its pads remain isolated.
 wire bench_enabled,filtered_key1_n,filtered_key2_n,view_toggle,long_ready;
 reg diagnostic_view=0;
 always @(posedge clk)if(!rst_n)diagnostic_view<=0;else if(view_toggle)diagnostic_view<=!diagnostic_view;
 bench_manual_enable #(.CLK_HZ(CLK_HZ)) manual(.clk(clk),.rst_n(rst_n),
  .key1_n(key1_n),.key2_n(key2_n),.enabled(bench_enabled),
  .filtered_key1_n(filtered_key1_n),.filtered_key2_n(filtered_key2_n),.view_toggle(view_toggle),.long_ready(long_ready));
 // In this explicitly named bench build the guard receives operator permission.
 // Supply loss is NOT detected. D15 remains unused, never strap it to 3V3.
 imu_io_guard #(.CLK_HZ(CLK_HZ)) io_guard(.clk(clk),.rst_n(rst_n),.power_good(BENCH_MANUAL ? bench_enabled : imu_power_good),
  .fault_latched(imu_fault || !AUTONOMOUS_UART),.spi(AUTONOMOUS_SPI!=0),
  .raw_tx(raw_imu_tx),.raw_cs_n(raw_imu_cs),.raw_mosi(raw_imu_mosi),.raw_rst_n(raw_imu_rst),.raw_wake_n(raw_imu_wake),
  .host_enable(imu_host_enable),.drive_enable(imu_drive_enable),
  .tx(imu_clk_tx),.cs_n(imu_cs_n),.mosi(imu_data),.sensor_rst_n(imu_rst_n),.wake_n(imu_wake));
 assign imu_mosi=1'bz;
 reg [31:0] ticks;always @(posedge clk)if(!rst_n)ticks<=0;else ticks<=ticks+1;
 // UI bring-up candidate is silent, including the onboard amplifier.
 assign pa_en=UI_ONLY ? 1'b1 : 1'b0;
 wire [3:0] selected_zone,demo_zone,gesture_zone;
 wire layout_cycle,layout_ready;reg [1:0] layout_profile=0;
 wire [3:0] note_count=layout_profile==1 ? 5 : layout_profile==2 ? 12 : 7;
 always @(posedge clk)if(!rst_n)layout_profile<=0;else if(layout_cycle)layout_profile<=layout_profile==2 ? 0 : layout_profile+1'b1;
 wire action_press,expression_hold,sensor_reset,sensor_online;
 wire menu_open;wire [2:0] menu_focus;wire [1:0] preset_id,release_id;
 wire delay_enabled;wire [3:0] delay_setting;wire [1:0] feedback_setting,wet_setting;
 wire test_requested;wire [4:0] test_voice;wire [31:0] mute_mask;
 wire test_config_valid,test_busy,test_ready;wire [127:0] test_config_data;
 wire sample_tick,sample_valid;wire [79:0] samples;wire [31:0] clips;
 wire [SYNTH_VOICES*16-1:0] all_envelopes,voice_samples;
 wire [SYNTH_VOICES-1:0] active_voices;
 wire [31:0] underflows,monitor_frequency,event_drops;
 wire [15:0] last_render_cycles,max_render_cycles,monitor_envelope;
 wire [1:0] monitor_stage;
 reg [47:0] monitor_hz_product;
 always @(posedge clk)monitor_hz_product<=monitor_frequency*16'd48000+48'd2147483648;
 instrument_keys #(.CLK_HZ(CLK_HZ),.ALLOW_TEST(SYNTH_VOICES==32 && !UI_ONLY),.ALLOW_MENU(!UI_ONLY),.ALLOW_LAYOUT(UI_ONLY)) keys(.clk(clk),.rst_n(rst_n),.key0_n(key0_n),.note_count(note_count),.layout_chord_free(key1_n && key2_n),.layout_cycle(layout_cycle),.layout_ready(layout_ready),.key1_n(BENCH_MANUAL ? filtered_key1_n : key1_n),
   .key2_n(BENCH_MANUAL ? filtered_key2_n : key2_n),.demo_mode(!sensor_online),.action_press(action_press),
   .expression_hold(expression_hold),.sensor_reset(sensor_reset),.demo_zone(demo_zone),
   .menu_open(menu_open),.menu_focus(menu_focus),.preset_id(preset_id),.release_id(release_id),
   .test_requested(test_requested),.test_voice(test_voice),.mute_mask(mute_mask),
   .delay_enabled(delay_enabled),.delay_setting(delay_setting),.feedback_setting(feedback_setting),.wet_setting(wet_setting));
 assign selected_zone=sensor_online ? gesture_zone : demo_zone;
 wire [7:0] rx_data;wire rx_valid,rx_start,rx_error;
 uart_rx #(.CLK_HZ(CLK_HZ)) pc_uart_rx(clk,rst_n,pc_rx,32'd921600,rx_data,rx_valid,rx_start,rx_error);
 wire cmd_done;wire [7:0] cmd;wire [15:0] cmd_seq;wire [6:0] cmd_len;wire [511:0] cmd_data;wire [31:0] cmd_errors;
 frame_rx command_rx(clk,rst_n,rx_data,rx_valid,cmd_done,cmd,cmd_seq,cmd_len,cmd_data,cmd_errors);
 wire voice_config=cmd_done && cmd==16 && cmd_len==16 && cmd_data[7:0]<4;
 reg audio_config_valid;
 reg audio_config_from_pc;
 reg [127:0] audio_config_data;
 wire local_config_valid;wire [127:0] local_config_data;
 wire gesture_note_on,velocity_update,pose_valid,calibrated,calibrating,gesture_armed;
 wire [1:0] last_trigger_reason;
 wire out_of_range,drift_warning,data_fresh,playable,sensor_restarted;
 wire signed [15:0] yaw,pitch,roll,bend_cents,vibrato_cents,downward_accel;
 wire signed [1:0] hit_octave;
 wire [7:0] velocity,gesture_event_id,brightness;
 wire [3:0] hit_zone;wire [1:0] hit_profile;wire [2:0] link_state,host_link_state;
 assign link_state=!imu_host_enable ? 3'd6 : host_link_state;
 wire [1:0] accuracy;
 wire [1:0] accel_accuracy,gyro_accuracy;wire [5:0] calibration_progress;wire [1:0] calibration_state;
 wire [4:0] feature_mask;
 wire [15:0] pose_hz,accel_hz,gyro_hz;
 wire [15:0] received_bytes,received_packets;wire [2:0] stream_fresh;
 wire [31:0] protocol_errors,sequence_gaps,reset_attempts,hit_count,pose_overruns,gesture_overruns,stolen_notes;
 wire expression_active;
 wire [63:0] voice_envelopes;
 wire [SYNTH_VOICES-1:0] local_owned,local_gates;
 wire [SYNTH_VOICES*3-1:0] local_zones;
 wire demo_note_on=action_press && !sensor_online && !test_busy && !test_requested;
 wire instrument_note_on=(gesture_note_on && !menu_open && !test_busy && !test_requested) || demo_note_on;
 reg previous_online;
 always @(posedge clk)if(!rst_n)previous_online<=0;else previous_online<=sensor_online;
 wire [11:0] ui_hit_mask;
 imu_ui_feedback #(.CLK_HZ(CLK_HZ),.ZONES(12)) ui_feedback(.clk(clk),.rst_n(rst_n),
  .clear(sensor_restarted || (previous_online && !sensor_online) || calibrating || layout_cycle),
  .hit_valid(instrument_note_on),.hit_zone(gesture_note_on ? hit_zone : demo_zone),.hit_mask(ui_hit_mask));
 reg [7:0] demo_event_id;
 reg [31:0] displayed_hits;
 reg [3:0] last_hit_zone;reg [1:0] last_hit_profile;
 reg [7:0] displayed_velocity;
 reg signed [1:0] displayed_octave;
 always @(posedge clk) begin
  if(!rst_n) begin demo_event_id<=0;displayed_hits<=0;last_hit_zone<=3;last_hit_profile<=0;displayed_velocity<=0;displayed_octave<=0;end
  else if(instrument_note_on) begin
   displayed_hits<=displayed_hits+1'b1;last_hit_zone<=gesture_note_on ? hit_zone : demo_zone;last_hit_profile<=gesture_note_on ? hit_profile : layout_profile;
   displayed_velocity<=gesture_note_on ? velocity : 80;
   displayed_octave<=gesture_note_on ? hit_octave : 2'sd0;
   if(demo_note_on) demo_event_id<=demo_event_id+1'b1;
  end else if(velocity_update) displayed_velocity<=velocity;
 end
 local_instrument #(.CLK_HZ(CLK_HZ),.VOICES(SYNTH_VOICES)) instrument(.clk(clk),.rst_n(rst_n),
  .enabled(!UI_ONLY && !menu_open && !test_busy && !test_requested && (!sensor_online || (calibrated && !calibrating && accuracy>=2))),
  .note_on(instrument_note_on),.velocity_update(velocity_update),
  .hit_zone(gesture_note_on ? hit_zone[2:0] : demo_zone[2:0]),.hit_octave(gesture_note_on ? hit_octave : 2'sd0),
  .velocity(sensor_online ? velocity : 8'd80),.event_id(sensor_online ? gesture_event_id : demo_event_id+1'b1),
  .bend_cents(bend_cents),.vibrato_cents(vibrato_cents),.envelopes(all_envelopes),
  .preset_enable(1'b1),.preset_id(preset_id),.release_id(release_id),
  .external_valid(voice_config || (test_config_valid && !voice_config)),
  .external_data(voice_config ? cmd_data[127:0] : test_config_data),
  .config_valid(local_config_valid),.config_data(local_config_data),.config_ready(!voice_config && !test_config_valid),
  .owned(local_owned),.gates(local_gates),.zones(local_zones),.stolen_notes(stolen_notes),.event_drops(event_drops));
 generate if(SYNTH_VOICES==32)begin: test_engine
  polyphony_test test_source(.clk(clk),.rst_n(rst_n),.requested(test_requested),.mute_mask(mute_mask),
   .sample_valid(sample_valid),.config_ready(!voice_config),.config_valid(test_config_valid),
   .config_data(test_config_data),.busy(test_busy),.ready(test_ready));
 end else begin assign test_config_valid=0;assign test_config_data=0;assign test_busy=0;assign test_ready=0;end endgenerate
 // Register the accepted command before the 32-entry audio/status fanout.
 // Arbitration still acknowledges exactly one source per cycle, in order.
 always @(posedge clk)begin
  if(!rst_n)begin audio_config_valid<=0;audio_config_from_pc<=0;audio_config_data<=0;end
  else begin
   audio_config_valid<=voice_config || test_config_valid || local_config_valid;
   audio_config_from_pc<=voice_config;
   audio_config_data<=voice_config ? cmd_data[127:0] : test_config_valid ? test_config_data : local_config_data;
  end
 end
 assign event_mark=instrument_note_on || voice_config;
 // Seven C-major note zones are derived only from accepted audio commands.
 // 7 means no matching diatonic note. This is a sounding-note indicator;
 // UI_ONLY instead uses the independent accepted-gesture flash mask.
 function [2:0] note_zone;
  input [31:0] step;
  reg [31:0] octave_step;
  begin
   octave_step=step;
   if(octave_step<32'd11300000) octave_step=octave_step<<2;
   else if(octave_step<32'd22700000) octave_step=octave_step<<1;
   else if(octave_step>=32'd91600000) octave_step=octave_step>>2;
   else if(octave_step>=32'd45800000) octave_step=octave_step>>1;
   note_zone=3'd7;
   if(octave_step>=32'd22941662 && octave_step<=32'd23878056) note_zone=0; // Do / C
   else if(octave_step>=32'd25751145 && octave_step<=32'd26802213) note_zone=1; // Re / D
   else if(octave_step>=32'd28904684 && octave_step<=32'd30084466) note_zone=2; // Mi / E
   else if(octave_step>=32'd30623445 && octave_step<=32'd31873381) note_zone=3; // Fa / F
   else if(octave_step>=32'd34373655 && octave_step<=32'd35776661) note_zone=4; // Sol / G
   else if(octave_step>=32'd38583123 && octave_step<=32'd40157945) note_zone=5; // La / A
   else if(octave_step>=32'd43308091 && octave_step<=32'd45075769) note_zone=6; // Si / B
  end
 endfunction
 reg [2:0] voice_zone[0:SYNTH_VOICES-1];
 reg [SYNTH_VOICES-1:0] voice_gate;
 reg [SYNTH_VOICES*2-1:0] voice_presets;reg [SYNTH_VOICES-1:0] preset_voices;
 reg [6:0] active_zones;
 integer zi;
 always @(posedge clk) begin
  if(!rst_n) begin
   voice_gate<=0;
   voice_presets<=0;preset_voices<=0;
   for(zi=0;zi<SYNTH_VOICES;zi=zi+1) voice_zone[zi]<=3'd7;
  end else if(audio_config_valid) begin
   voice_gate[audio_config_data[$clog2(SYNTH_VOICES)-1:0]]<=audio_config_data[56];
   voice_presets[audio_config_data[$clog2(SYNTH_VOICES)-1:0]*2+:2]<=audio_config_data[51:50];
   preset_voices[audio_config_data[$clog2(SYNTH_VOICES)-1:0]]<=audio_config_data[55];
   if(audio_config_from_pc || audio_config_data[58]) voice_zone[audio_config_data[$clog2(SYNTH_VOICES)-1:0]]<=
     audio_config_data[57] ? local_zones[audio_config_data[$clog2(SYNTH_VOICES)-1:0]*3+:3] : note_zone(audio_config_data[39:8]);
  end
 end
 integer zm;
 always @* begin
  active_zones=0;
  for(zm=0;zm<SYNTH_VOICES;zm=zm+1)
   if((voice_gate[zm] || all_envelopes[zm*16+:16]!=0) && voice_zone[zm]<7)
    active_zones[voice_zone[zm]]=1'b1;
 end
 // Silent HDMI/IMU profile has no synthesizer. Gesture feedback is independent.
 generate if(!UI_ONLY)begin: synthesis_engine
 audio_core #(.VOICES(SYNTH_VOICES),.MASTER_SHIFT(SYNTH_VOICES==32 ? 3 : 0)) audio(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.config_valid(audio_config_valid),.config_data(audio_config_data),
  .samples(samples),.sample_valid(sample_valid),.clips(clips),.local_brightness(brightness),.envelopes(voice_envelopes),
  .all_envelopes(all_envelopes),.voice_samples(voice_samples),.active_voices(active_voices),
  .underflows(underflows),.last_render_cycles(last_render_cycles),.max_render_cycles(max_render_cycles),
  .monitor_voice(test_voice[$clog2(SYNTH_VOICES)-1:0]),.monitor_frequency(monitor_frequency),
  .monitor_envelope(monitor_envelope),.monitor_stage(monitor_stage));
 end else begin: silent_engine
  assign samples=0;assign sample_valid=0;assign clips=0;assign voice_envelopes=0;
  assign all_envelopes=0;assign voice_samples=0;assign active_voices=0;
  assign underflows=0;assign last_render_cycles=0;assign max_render_cycles=0;
  assign monitor_frequency=0;assign monitor_envelope=0;assign monitor_stage=0;
 end endgenerate
 wire test_audio_bypass=test_requested || test_busy;
 wire [15:0] delay_samples=16'd2880+delay_setting*16'd1440;
 wire [15:0] delay_ms=16'd60+delay_setting*16'd30;
 wire signed [23:0] delay_left,delay_right;
 wire delay_valid,delay_busy;wire [15:0] actual_delay_samples,actual_wet_q15,delay_max_cycles;
 wire [31:0] delay_clips,delay_overruns;
 generate if(!UI_ONLY)begin: effects
 audio_delay delay_fx(.clk(clk),.rst_n(rst_n),.clear(test_audio_bypass),.sample_valid(sample_valid),
  .input_left({samples[79:64],8'b0}),.input_right({samples[79:64],8'b0}),
  .enabled(delay_enabled),.delay_samples(delay_samples),.feedback_setting(feedback_setting),.wet_setting(wet_setting),
  .output_left(delay_left),.output_right(delay_right),.output_valid(delay_valid),.busy(delay_busy),
  .actual_delay_samples(actual_delay_samples),.actual_wet_q15(actual_wet_q15),
  .clips(delay_clips),.overruns(delay_overruns),.max_render_cycles(delay_max_cycles));
 end else begin
  assign delay_left=0;assign delay_right=0;assign delay_valid=0;assign delay_busy=0;
  assign actual_delay_samples=0;assign actual_wet_q15=0;assign delay_max_cycles=0;
  assign delay_clips=0;assign delay_overruns=0;
 end endgenerate
 wire [15:0] dac_left=UI_ONLY ? 16'd0 : test_audio_bypass ? samples[79:64] : delay_left[23:8];
 wire [15:0] dac_right=UI_ONLY ? 16'd0 : test_audio_bypass ? samples[79:64] : delay_right[23:8];
 wire [79:0] display_samples={dac_left,samples[63:0]};
 wire display_sample_valid=test_audio_bypass ? sample_valid : delay_valid;
 function [3:0] count8;
  input [7:0] bits;
  begin count8=({3'b0,bits[0]}+bits[1])+({3'b0,bits[2]}+bits[3])+({3'b0,bits[4]}+bits[5])+({3'b0,bits[6]}+bits[7]);end
 endfunction
 wire [31:0] active_mask=active_voices;
 wire [5:0] audible_count=({2'b0,count8(active_mask[7:0])}+count8(active_mask[15:8]))+
                         ({2'b0,count8(active_mask[23:16])}+count8(active_mask[31:24]));
 wire [255:0] voice_levels;
 genvar vl;
 generate for(vl=0;vl<32;vl=vl+1)begin: envelope_levels
  if(vl<SYNTH_VOICES)assign voice_levels[vl*8+:8]=all_envelopes[vl*16+8+:8];
  else assign voice_levels[vl*8+:8]=0;
 end endgenerate
 reg [1023:0] performance_status;
 always @* begin
  performance_status=0;
  performance_status[3:0]=!sensor_online ? 0 : calibration_state==3 ? 9 : accuracy<2 ? 3 :
    calibrating ? (calibration_state==2 ? 10 : 1) : !calibrated ? 2 : drift_warning ? 4 : out_of_range ? 5 : !data_fresh ? 6 : gesture_armed ? 7 : 8;
  performance_status[5:4]=accuracy;performance_status[6]=sensor_online;performance_status[7]=calibrated;
  performance_status[8]=calibrating;performance_status[9]=gesture_armed;
  performance_status[10]=out_of_range;performance_status[11]=drift_warning;
  performance_status[12]=expression_active;performance_status[13]=!sensor_online;performance_status[14]=data_fresh;
  performance_status[15]=displayed_hits!=0;
  performance_status[31:16]=yaw;performance_status[47:32]=pitch;performance_status[63:48]=roll;
  performance_status[79:64]=bend_cents;performance_status[95:80]=vibrato_cents;
  performance_status[103:96]=brightness;performance_status[111:104]=displayed_velocity;
  performance_status[127:112]=pose_hz;performance_status[143:128]=accel_hz;performance_status[159:144]=gyro_hz;
  performance_status[191:160]=protocol_errors;performance_status[223:192]=displayed_hits;
  performance_status[226:224]=last_hit_zone;performance_status[232:227]=calibration_progress;
  performance_status[239:233]=UI_ONLY ? ui_hit_mask[6:0] : active_zones;performance_status[242:240]=selected_zone;
  performance_status[246:243]=voice_gate[3:0];performance_status[249:247]=link_state;performance_status[254:250]=feature_mask;
  performance_status[263:256]=voice_presets[7:0];performance_status[267:264]=preset_voices[3:0];
  performance_status[269:268]=preset_id;performance_status[270]=menu_open;
  performance_status[272:271]=release_id;performance_status[273]=menu_focus[0];performance_status[306]=menu_focus[1];
  performance_status[307]=menu_focus[2];
  performance_status[305:274]=clips;
  performance_status[351:320]=active_voices;performance_status[383:352]=mute_mask;
  performance_status[388:384]=test_voice;performance_status[389]=test_requested || test_busy;
  performance_status[390]=test_ready;performance_status[422:391]=underflows;
  performance_status[438:423]=max_render_cycles;performance_status[454:439]=monitor_hz_product[47:32];
  performance_status[456:455]=monitor_stage;performance_status[472:457]=monitor_envelope;
  performance_status[728:473]=voice_levels;performance_status[760:729]=event_drops;performance_status[766:761]=audible_count;
  performance_status[768]=delay_enabled;performance_status[769]=test_audio_bypass;
  performance_status[773:770]=delay_setting;performance_status[775:774]=feedback_setting;
  performance_status[777:776]=wet_setting;performance_status[793:778]=actual_delay_samples;
  performance_status[809:794]=actual_wet_q15;performance_status[825:810]=delay_max_cycles;
  performance_status[857:826]=delay_clips;performance_status[889:858]=delay_overruns;
  performance_status[905:890]=delay_ms;
  performance_status[906]=UI_ONLY;performance_status[913:907]=ui_hit_mask[6:0];
  performance_status[929:914]=received_bytes;performance_status[945:930]=received_packets;
  performance_status[961:946]=reset_attempts>65535 ? 16'hffff : reset_attempts[15:0];
  performance_status[964:962]=stream_fresh;performance_status[965]=AUTONOMOUS_SPI;
  // Octave of the last accepted hit, held independently of later Roll movement.
  performance_status[967:966]=displayed_octave;
  performance_status[968]=BENCH_MANUAL;performance_status[969]=bench_enabled;
  performance_status[973:970]=failure_reason;performance_status[989:974]=failure_header;
  performance_status[991:990]=failure_inputs;performance_status[995:992]=first_failure_reason;performance_status[996]=address_ack;performance_status[998:997]=calibration_state;performance_status[1000:999]=accel_accuracy;performance_status[1002:1001]=gyro_accuracy;performance_status[1003]=diagnostic_view;performance_status[1004]=long_ready;
  performance_status[1008:1005]=selected_zone;performance_status[1012:1009]=last_hit_zone;
  performance_status[1014:1013]=layout_profile;performance_status[1016:1015]=last_hit_profile;
  performance_status[1020:1017]=note_count;performance_status[1021]=1;performance_status[1022]=layout_ready;
  performance_status[331:320]=ui_hit_mask;performance_status[309:308]=last_trigger_reason;
 end
 video_hdmi display(.clk50(clk),.rst_n(rst_n),.samples(display_samples),.sample_valid(display_sample_valid),
                    .performance_status(performance_status),
                    .tmds_clk_p(tmds_clk_p_0),.tmds_clk_n(tmds_clk_n_0),
                    .tmds_d_p(tmds_d_p_0),.tmds_d_n(tmds_d_n_0));
 // The ordinary Dock uses PT8211 Japanese/LSBJ timing, not Philips I2S.
 // The present mixer is mono; duplicate it at this explicit stereo boundary.
 pt8211_output #(.CLK_HZ(CLK_HZ)) i2s(.clk(clk),.rst_n(rst_n),
  .pcm_left(dac_left),.pcm_right(dac_right),
  .bck(hp_bck),.ws(hp_ws),.dout(hp_din),.sample_tick(sample_tick));
 assign audio_mark=sample_tick;
 wire mode_valid=cmd_done && cmd==18 && cmd_len==1 && cmd_data[7:0]<3;
 wire imu_tx_busy;wire imu_tx_req=cmd_done && cmd==19 && cmd_len>0 && !imu_tx_busy;
 wire imu_ready;reg imu_take;wire [9:0] imu_len;wire [7:0] imu_byte;wire [31:0] imu_t0,imu_t1,imu_t2,imu_drops;wire [1:0] imu_mode;
 wire [15:0] tx_addr;
 wire [9:0] imu_addr=tx_addr-13;
 generate if(AUTONOMOUS_UART) begin: autonomous
  wire quat_valid,accel_valid,gyro_valid,gravity_valid,linear_valid;
  wire [7:0] linear_sequence;wire [31:0] linear_timestamp_ticks;wire linear_timestamp_valid;
  wire signed [15:0] qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz;
  bno_imu_host #(.REPORT_BACKPRESSURE(1),.SPI(AUTONOMOUS_SPI),.CLK_HZ(CLK_HZ)) host(.clk(clk),.rst_n(rst_n && imu_host_enable),.force_reset(sensor_reset),.rx(host_rx),.scl_in(host_scl),.address_ack(address_ack),.int_n(host_int_n),.cs_n(raw_imu_cs),.mosi(raw_imu_mosi),.wake_n(raw_imu_wake),
   .tx(raw_imu_tx),.sensor_rst_n(raw_imu_rst),.fault_latched(imu_fault),.first_failure_reason(first_failure_reason),.failure_reason(failure_reason),.failure_header(failure_header),.failure_inputs(failure_inputs),.online(sensor_online),.feature_mask(feature_mask),.link_state(host_link_state),
   .reset_attempts(reset_attempts),.quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.accel_accuracy(accel_accuracy),.gyro_accuracy(gyro_accuracy),
   .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),.linear_ready(1'b1),.linear_sequence(linear_sequence),
   .linear_timestamp_ticks(linear_timestamp_ticks),.linear_timestamp_valid(linear_timestamp_valid),
   .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),
   .lx(lx),.ly(ly),.lz(lz),.pose_hz(pose_hz),.accel_hz(accel_hz),.gyro_hz(gyro_hz),
   .protocol_errors(protocol_errors),.sequence_gaps(sequence_gaps),.sensor_restarted(sensor_restarted),
   .received_bytes(received_bytes),.received_packets(received_packets),.stream_fresh(stream_fresh));
  quaternion_pose #(.CLK_HZ(CLK_HZ)) pose(.clk(clk),.rst_n(rst_n),.sensor_restarted(sensor_restarted),.online(sensor_online),
   .calibrate(action_press && sensor_online),.quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.gx(gx),.gy(gy),.gz(gz),
   .calibrated(calibrated),.calibrating(calibrating),.pose_valid(pose_valid),.yaw(yaw),.pitch(pitch),.roll(roll),
   .calibration_progress(calibration_progress),.calibration_state(calibration_state),.overruns(pose_overruns));
  gesture_control #(.CLK_HZ(CLK_HZ)) gestures(.clk(clk),.rst_n(rst_n),.sensor_restarted(sensor_restarted),
   .online(sensor_online),.calibrated(calibrated),.calibrating(calibrating),.accuracy(accuracy),.pose_valid(pose_valid),.yaw(yaw),.pitch(pitch),.roll(roll),
   .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
   .gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),
   .linear_valid(linear_valid),.linear_sequence(linear_sequence),.linear_timestamp_ticks(linear_timestamp_ticks),
   .linear_timestamp_valid(linear_timestamp_valid),.lx(lx),.ly(ly),.lz(lz),.layout_profile(layout_profile),.hit_profile(hit_profile),.selected_zone(gesture_zone),
   .out_of_range(out_of_range),.drift_warning(drift_warning),.data_fresh(data_fresh),.playable(playable),.armed(gesture_armed),
   .note_on(gesture_note_on),.velocity_update(velocity_update),.velocity(velocity),.hit_zone(hit_zone),.hit_octave(hit_octave),
   .hit_count(hit_count),.event_id(gesture_event_id),.last_trigger_reason(last_trigger_reason),.downward_accel(downward_accel),.processing_overruns(gesture_overruns));

  assign imu_tx_busy=0;assign imu_ready=0;assign imu_len=0;assign imu_byte=0;
  assign imu_t0=0;assign imu_t1=0;assign imu_t2=0;assign imu_drops=protocol_errors;assign imu_mode=1;
 end else begin: legacy
  assign imu_fault=1'b1;
  imu_transport #(.CLK_HZ(CLK_HZ)) imu(clk,1'b0,ticks,mode_valid,cmd_data[1:0],imu_tx_req,cmd_len,cmd_data,imu_tx_busy,
   host_rx,host_int_n,raw_imu_tx,raw_imu_cs,raw_imu_mosi,raw_imu_rst,raw_imu_wake,imu_ready,imu_take,imu_len,imu_addr,imu_byte,imu_t0,imu_t1,imu_t2,imu_drops,imu_mode);
  assign sensor_online=0;assign sensor_restarted=0;assign gesture_zone=3;assign gesture_note_on=0;assign velocity_update=0;
  assign last_trigger_reason=0;assign pose_valid=0;assign calibrated=0;assign calibrating=0;assign gesture_armed=0;assign out_of_range=0;assign drift_warning=0;
  assign data_fresh=0;assign playable=0;assign accuracy=0;assign yaw=0;assign pitch=0;assign roll=0;assign hit_octave=0;
  assign velocity=0;assign hit_profile=0;assign hit_zone=3;assign hit_count=0;assign gesture_event_id=0;assign downward_accel=0;
  assign host_link_state=5;assign feature_mask=0;assign reset_attempts=0;assign pose_hz=0;assign accel_hz=0;assign gyro_hz=0;
  assign accel_accuracy=0;assign gyro_accuracy=0;assign protocol_errors=imu_drops;assign sequence_gaps=0;assign calibration_progress=0;assign calibration_state=0;assign pose_overruns=0;assign gesture_overruns=0;
  assign received_bytes=0;assign received_packets=0;assign stream_fresh=0;
 end endgenerate
 hand_expression expression(.clk(clk),.rst_n(rst_n),.sensor_restarted(sensor_restarted),.playable(playable),
  .express(expression_hold),.pose_valid(pose_valid),.roll(roll),.pitch(pitch),.bend_cents(bend_cents),.vibrato_cents(vibrato_cents),
  .brightness(brightness),.expression_active(expression_active));
 reg [79:0] capture_mem[0:2047];reg [10:0] cap_wr;reg capture_active,armed,cap_ready;reg [15:0] capture_id,upload_offset;
 reg signed [15:0] previous_mix;
 reg [79:0] cap_word;
 wire [15:0] sample_index=upload_offset+(tx_addr-10)/10;
 always @(posedge clk)cap_word<=capture_mem[sample_index[10:0]];
 reg preview_on;reg [8:0] preview_count;
 reg signed [15:0] minima[0:4],maxima[0:4];
 reg [159:0] envelope;reg envelope_ready;integer j;
 reg [31:0] status_timer;reg status_pending;
 reg response_pending;reg [7:0] response_kind,response_code;reg [15:0] response_seq;
 reg tx_start;reg [7:0] tx_kind;reg [15:0] tx_len;reg [7:0] tx_payload;
 wire [7:0] tx_byte;wire tx_valid,tx_uart_ready,tx_busy,tx_done;
 reg [15:0] saved_seq;reg [7:0] saved_code;reg [31:0] saved_tick;
 frame_tx transmitter(clk,rst_n,tx_start,tx_kind,tx_len,saved_tick,tx_addr,tx_payload,tx_byte,tx_valid,tx_uart_ready,tx_busy,tx_done);
 uart_tx #(.CLK_HZ(CLK_HZ)) pc_uart_tx(clk,rst_n,32'd921600,tx_byte,tx_valid,tx_uart_ready,pc_tx);
 reg [31:0] tx_drops;reg [31:0] snap_drops,snap_clips;
 // Allow the onboard USB-UART bridge to drain between capture packets.
 reg [19:0] capture_gap;
 reg [159:0] snap_envelope;
 wire [31:0] sample_rate=48000;wire [31:0] clock_rate=CLK_HZ;
 reg [255:0] info_bytes;
 always @*begin
  info_bytes=0;
  info_bytes[15:0]=saved_seq;info_bytes[47:16]=clock_rate;info_bytes[79:48]=sample_rate;
  info_bytes[87:80]=SYNTH_VOICES;info_bytes[103:88]=2048;
  info_bytes[111:104]="T";info_bytes[119:112]="a";info_bytes[127:120]="n";info_bytes[135:128]="g";
  info_bytes[143:136]="L";info_bytes[151:144]="a";info_bytes[159:152]="b";info_bytes[167:160]=" ";
  info_bytes[175:168]="1";info_bytes[183:176]=".";info_bytes[191:184]="0";
  tx_payload=0;
  case(tx_kind)
   128:tx_payload=info_bytes[tx_addr*8+:8];
   129,134:case(tx_addr)0:tx_payload=saved_seq[7:0];1:tx_payload=saved_seq[15:8];2:tx_payload=saved_code;endcase
   130:case(tx_addr)
    0:tx_payload=capture_id[7:0];1:tx_payload=capture_id[15:8];
    2:tx_payload=upload_offset[7:0];3:tx_payload=upload_offset[15:8];
    4:tx_payload=0;5:tx_payload=8;6:tx_payload=sample_rate[7:0];7:tx_payload=sample_rate[15:8];8:tx_payload=0;9:tx_payload=0;
    default:tx_payload=cap_word[((tx_addr-10)%10)*8+:8];
   endcase
   131:tx_payload=snap_envelope[tx_addr*8+:8];
   132:begin
    if(tx_addr==0)tx_payload={6'b0,imu_mode};
    else if(tx_addr<5)tx_payload=imu_t0[(tx_addr-1)*8+:8];
    else if(tx_addr<9)tx_payload=imu_t1[(tx_addr-5)*8+:8];
    else if(tx_addr<13)tx_payload=imu_t2[(tx_addr-9)*8+:8];
    else tx_payload=imu_byte;
   end
   133:if(tx_addr<4)tx_payload=snap_drops[tx_addr*8+:8];else tx_payload=snap_clips[(tx_addr-4)*8+:8];
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   capture_gap<=0;
   capture_active<=0;armed<=0;cap_ready<=0;cap_wr<=0;capture_id<=0;upload_offset<=0;previous_mix<=0;
   preview_on<=0;preview_count<=0;envelope<=0;envelope_ready<=0;status_timer<=0;status_pending<=0;
   response_pending<=0;response_kind<=0;response_code<=0;response_seq<=0;tx_start<=0;tx_kind<=0;tx_len<=0;imu_take<=0;
   saved_seq<=0;saved_code<=0;saved_tick<=0;tx_drops<=0;snap_drops<=0;snap_clips<=0;snap_envelope<=0;
   for(j=0;j<5;j=j+1)begin minima[j]<=32767;maxima[j]<=-32768;end
  end else begin
   tx_start<=0;imu_take<=0;
   if(capture_gap!=0)capture_gap<=capture_gap-1;
   if(status_timer==CLK_HZ-1)begin status_timer<=0;status_pending<=1;end else status_timer<=status_timer+1;
   if(sample_valid)begin
    previous_mix<=samples[79:64];
    if(armed && previous_mix<0 && $signed(samples[79:64])>=0)begin armed<=0;capture_active<=1;cap_wr<=0;end
    if(capture_active)begin
     capture_mem[cap_wr]<=samples;
     if(cap_wr==2047)begin capture_active<=0;cap_ready<=1;upload_offset<=0;end else cap_wr<=cap_wr+1;
    end
    for(j=0;j<5;j=j+1)begin
     if($signed(samples[j*16+:16])<minima[j])minima[j]<=samples[j*16+:16];
     if($signed(samples[j*16+:16])>maxima[j])maxima[j]<=samples[j*16+:16];
     if(preview_count==479)begin
      envelope[j*32+:16]<=$signed(samples[j*16+:16])<minima[j]?samples[j*16+:16]:minima[j];
      envelope[j*32+16+:16]<=$signed(samples[j*16+:16])>maxima[j]?samples[j*16+:16]:maxima[j];
      minima[j]<=32767;maxima[j]<=-32768;
     end
    end
    if(preview_count==479)begin preview_count<=0;if(preview_on)envelope_ready<=1;end else preview_count<=preview_count+1;
   end
   if(cmd_done)begin
    if(response_pending)tx_drops<=tx_drops+1;
    response_pending<=1;response_seq<=cmd_seq;response_kind<=129;response_code<=0;
    case(cmd)
     1:response_kind<=128;
     16:if(cmd_len!=16 || cmd_data[7:0]>3)response_code<=2;
     17:if(capture_active || armed || cap_ready)response_code<=1;
        else begin capture_id<=capture_id+1;cap_wr<=0;armed<=cmd_data[0];capture_active<=!cmd_data[0];end
     18:if(AUTONOMOUS_UART || cmd_len!=1 || cmd_data[7:0]>2)response_code<=2;
     19:if(AUTONOMOUS_UART)response_code<=2;else if(imu_tx_busy)response_code<=1;else if(cmd_len==0 || imu_mode==0)response_code<=2;
     20:response_kind<=134;
     21:preview_on<=cmd_data[0];
     default:response_code<=2;
    endcase
   end
   if(!tx_busy && !tx_start && !tx_done)begin
    saved_tick<=ticks;
    if(response_pending)begin
     saved_seq<=response_seq;saved_code<=response_code;tx_kind<=response_kind;tx_len<=response_kind==128?24:3;
     tx_start<=1;response_pending<=0;
    end else if(imu_ready && !imu_take)begin tx_kind<=132;tx_len<=imu_len+13;tx_start<=1;end
    else if(status_pending)begin tx_kind<=133;tx_len<=8;snap_drops<=imu_drops+tx_drops+cmd_errors;snap_clips<=clips;status_pending<=0;tx_start<=1;end
    else if(envelope_ready && preview_on)begin tx_kind<=131;tx_len<=20;snap_envelope<=envelope;envelope_ready<=0;tx_start<=1;end
    else if(cap_ready && capture_gap==0)begin tx_kind<=130;tx_len<=330;tx_start<=1;end
   end
   if(tx_done)begin
    if(tx_kind==132)imu_take<=1;
    if(tx_kind==130)begin
     capture_gap<=CLK_HZ/100; // 10 ms; sample acquisition remains 48 kHz.
     if(upload_offset==2016)cap_ready<=0;else upload_offset<=upload_offset+32;
    end
   end
  end
 end
endmodule
