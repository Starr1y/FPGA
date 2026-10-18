// DUO04: shared dual-IMU/offline, mouse and teaching instrument.
module top_duo04 #(parameter BOOT_CYCLES=524288, WATCHDOG_CYCLES=100000000, KEY_DEBOUNCE=1000000, CAPTURE_GAP_CYCLES=500000)(
 input clk,reset_key,key0_n,key1_n,key2_n,pc_rx,
 input encoder_a,encoder_b,encoder_button_n,
 inout[1:0]imu_scl,imu_sda,imu_rst_n,input[1:0]imu_int_n,
 output hp_bck,hp_ws,hp_din,pa_en,pc_tx,
 output i2s_bck,i2s_ws,i2s_dout,
 output tmds_clk_p_0,tmds_clk_n_0,output[2:0]tmds_d_p_0,tmds_d_n_0);
 wire core_clk,serial_clk,pixel_clk,pll_lock;
`ifdef TANG_SIM
 assign core_clk=clk;assign serial_clk=clk;assign pixel_clk=clk;assign pll_lock=1;
`else
 duo04_pll main_pll(.clkin(clk),.core_clk(core_clk),.clkout0(serial_clk),.clkout1(pixel_clk),.lock(pll_lock));
`endif
 reg[2:0]core_reset_pipe=0;
 always @(posedge core_clk or negedge pll_lock)begin
  if(!pll_lock)core_reset_pipe<=0;else core_reset_pipe<={core_reset_pipe[1:0],1'b1};
 end
 wire[1:0]scl_low,sda_low,reset_low,online;
 genvar pad;generate for(pad=0;pad<2;pad=pad+1)begin:pads
  assign imu_scl[pad]=scl_low[pad] ? 1'b0 : 1'bz;
  assign imu_sda[pad]=sda_low[pad] ? 1'b0 : 1'bz;
  assign imu_rst_n[pad]=reset_low[pad] ? 1'b0 : 1'bz;
 end endgenerate
 reg[19:0]boot=0;reg[1:0]reset_sync=0;
 always @(posedge core_clk)begin if(boot<BOOT_CYCLES)boot<=boot+1'b1;reset_sync<={reset_sync[0],reset_key};end
 wire rst_n=core_reset_pipe[2] && boot>=BOOT_CYCLES && !reset_sync[1];
 reg[1:0]operating_mode;reg[1:0]octave_left,octave_right;reg[1:0]lesson_song;
 reg lesson_restart;reg[1:0]calibrate;
 wire local_step,local_direction,local_short,local_long;
 wire[11:0]key_actions;wire ui_stop,ui_hand;wire[2:0]ui_level,ui_group;wire[3:0]ui_item;wire[7:0]ui_notice;
 wire remote_ui;
 wire[15:0]ui_serial;reg lesson_clear;
 reg lesson_mouse,lesson_saved;reg[3:0]saved_profiles,saved_octaves;reg saved_chord;
 reg[1:0]sensor_force_reset;reg[1:0]calibration_result;reg[1:0]calibration_mask;reg[31:0]calibration_age;reg calibration_seen;
 wire use_host=operating_mode==1 || (operating_mode==2 && lesson_mouse);
 wire[1:0]lesson_phase;wire feedback_hand;wire[3:0]feedback_zone;wire[15:0]lesson_serial;
 wire key_stop=key_actions[11] || ui_stop;
 wire[1:0]wrist_short,wrist_long;wire[3:0]buttons_ready;wire[15:0]encoder_errors;wire unused_pedal;

 wire[1:0]menu_page;wire[4:0]menu_field;wire menu_editing,menu_write;wire[15:0]menu_value;reg[15:0]menu_current;

 wire[1:0]sensor_release,sensor_ack;wire[63:0]sensor_epochs,sensor_events,sensor_drops,sensor_cancelled,sensor_overruns;wire[95:0]sensor_rates;wire[511:0]sensor_status;wire sensor_valid,sensor_ready;

 wire[6:0]lesson_note;wire mapped_valid;wire[6:0]played_note;
 wire[63:0]mapped_sensor_events={sensor_events[63:23],(operating_mode==2 ? 2'b00 : (sensor_events[29] ? octave_right : octave_left)),sensor_events[20:0]};

 wire[4:0]lesson_position;wire[15:0]lesson_correct,lesson_wrong;wire lesson_hand,lesson_finished,lesson_feedback;wire[3:0]lesson_zone;

 wire[31:0]expired_unused;
 reg[31:0]ticks,link_age;reg running;reg[7:0]stop_reason;
 reg[3:0]profiles;reg[5:0]presets;reg chord;reg[1:0]effect_mode;reg[7:0]wet;reg[8:0]test_gain;
 reg[1:0]piano_hold;reg[31:0]piano_coefficients;
 reg[15:0]hold_ms_left,hold_ms_right;reg[31:0]hold_samples_left,hold_samples_right;reg[3:0]release_ids;
 reg[1:0]selected_valid;reg[7:0]selected_zone,hit_zone;reg[3:0]hit_profile;
 reg[31:0]hits0,hits1,last_event,skipped_captures;reg last_hand;reg[6:0]last_velocity;
 reg[15:0]config_revision;
 wire sample_tick;
 reg[127:0]expression_config;
 wire[63:0]vibrato_rate={expression_config[95:64],expression_config[31:0]};
 wire[15:0]vibrato_depth={expression_config[103:96],expression_config[39:32]};
 wire[47:0]glide_steps={expression_config[127:104],(chord ? 24'd0 : expression_config[63:40])};
 wire[39:0]vibrato_ratios;
 performance_vibrato expression_lfo(.clk(core_clk),.rst_n(rst_n),.sample_tick(sample_tick),.rate_words(vibrato_rate),.depth_cents(vibrato_depth),.ratios(vibrato_ratios));
 reg sine_enable,sine_mode;reg[31:0]sine_frequency;reg[15:0]sine_amplitude;reg[1:0]sine_channels;
 wire sine_active,sine_valid,music_valid,music_off;wire signed[15:0]sine_left,sine_right,music_left,music_right;
 reg[2:0]monitor_count,cap_monitor_count;reg[31:0]monitor_ids,cap_monitor_ids;
 reg[63:0]held_voices;reg upload_voice,voice_meta_pending;
 wire[7:0]rx_byte;wire rx_valid;wire[31:0]rx_errors;
 uart_rx rx(.clk(core_clk),.rst_n(rst_n),.rx(pc_rx),.baud(32'd921600),.data(rx_byte),.valid(rx_valid),.start(),.error());
 wire cmd_done;wire[7:0]cmd;wire[15:0]cmd_seq;wire[6:0]cmd_len;wire[511:0]cmd_data;
 assign remote_ui=cmd_done && cmd==61 && cmd_len==1 && cmd_data[7:0]<12 && (cmd_data[7:0]==11 || !(local_step || local_short || local_long || key_actions!=0));
 frame_rx commands(core_clk,rst_n,rx_byte,rx_valid,cmd_done,cmd,cmd_seq,cmd_len,cmd_data,rx_errors);
 reg[1:0]push,cancel,clear_history;reg[63:0]push_data;wire[1:0]accepted,release_pending,release_ack;
 wire[63:0]epochs,events,drops,cancelled;wire event_valid,event_ready;
 wire host_valid,host_ready;wire[63:0]host_events,host_epochs;wire[1:0]host_release;wire[1:0]host_ack;
 assign event_valid=running && (use_host ? host_valid : sensor_valid);
 assign events=use_host ? host_events : mapped_sensor_events;
 assign epochs=use_host ? host_epochs : sensor_epochs;
 assign release_pending=host_release | sensor_release;
 assign host_ack=release_ack;assign sensor_ack=release_ack;
 assign host_ready=use_host && (running ? event_ready : 1'b1);assign sensor_ready=!use_host && (running ? event_ready : 1'b1);
 two_hand_event_queue #(.DEPTH(8)) queue(.clk(core_clk),.rst_n(rst_n),.push_valid(push),.push_payload(push_data),
  .cancel(cancel),.release_ack(host_ack),.release_pending(host_release),.epochs(host_epochs),
  .event_valid(host_valid),.event_ready(host_ready),.event_data(host_events),.drops(drops),.cancelled_events(cancelled),.accepted(accepted));
 wire sample_valid;wire[79:0]samples;wire signed[15:0]dry_left,dry_right;
 wire[31:0]clips,stereo_clips,underflows,invalid,stolen,owned,gates,active;
 wire[223:0]notes;wire[511:0]envelopes,voice_samples;wire[15:0]max_render;
 wire committed,committed_hand;wire[7:0]committed_id;
 two_hand_synth #(.VOICES(32),.CLK_HZ(50000000),.ENABLE_EXPRESSION(1)) synth(
  .clk(core_clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(event_valid),.event_ready(event_ready),.event_data(events),
  .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.chord_mode(chord && operating_mode!=2),.preset_ids(presets),.release_ids(release_ids),
  .hold_samples_left(hold_samples_left),.hold_samples_right(hold_samples_right),
  .piano_hold(piano_hold),.piano_coefficients(piano_coefficients),
  .glide_coefficients(glide_steps),.vibrato_ratios(vibrato_ratios),.bend_cents(use_host ? 32'b0 : {sensor_status[351:336],sensor_status[95:80]}),.vibrato_cents(32'b0),.brightness(use_host ? 16'h8080 : {sensor_status[375:368],sensor_status[119:112]}),.samples(samples),.sample_valid(sample_valid),
  .clips(clips),.underflows(underflows),.stereo_left(dry_left),.stereo_right(dry_right),.stereo_clips(stereo_clips),
  .owned(owned),.gates(gates),.active_voices(active),.notes(notes),.envelopes(envelopes),.voice_samples(voice_samples),
  .invalid_events(invalid),.stolen_notes(stolen),.max_render_cycles(max_render),
  .monitor_voice(5'b0),.monitor_frequency(),.monitor_envelope(),.monitor_stage(),
  .committed(committed),.committed_id(committed_id),.committed_hand(committed_hand));
 wire signed[15:0]pcm_left,pcm_right;wire pcm_valid,input_accepted;wire[1:0]active_effect;wire[7:0]actual_wet;wire[8:0]gain;
 wire[31:0]fx_drops,fx_clips;
 stereo_output_path #(.MAKEUP_SHIFT(3)) audio_path(.clk(core_clk),.rst_n(rst_n),.in_valid(sample_valid),.in_left(dry_left),.in_right(dry_right),
  .muted(!running),.test_gain(test_gain),.input_accepted(input_accepted),.requested_mode(effect_mode),.requested_wet(wet),.clear_history(clear_history),
  .pcm_left(music_left),.pcm_right(music_right),.pcm_valid(music_valid),.active_mode(active_effect),.actual_wet(actual_wet),
  .master_gain(gain),.amplifier_off(music_off),.fx_drops(fx_drops),.fx_clips(fx_clips));
 sine_calibrator calibration(.clk(core_clk),.rst_n(rst_n),.sample_tick(sample_tick),.enable(sine_enable),.frequency(sine_frequency),.amplitude(sine_amplitude),.channels(sine_channels),
  .active(sine_active),.valid(sine_valid),.left(sine_left),.right(sine_right));
 assign pcm_left=sine_mode ? sine_left : music_left;assign pcm_right=sine_mode ? sine_right : music_right;
 assign pcm_valid=sine_mode ? sine_valid : music_valid;assign pa_en=sine_mode ? !sine_active : music_off;
 stereo_serial_output dac(.clk(core_clk),.rst_n(rst_n),.pcm_left(pcm_left),.pcm_right(pcm_right),.bck(hp_bck),.ws(hp_ws),.dout(hp_din),.sample_tick(sample_tick),.i2s_bck(i2s_bck),.i2s_ws(i2s_ws),.i2s_dout(i2s_dout));

 duo04_keys keys(.clk(core_clk),.rst_n(rst_n),.key_n({key2_n,key1_n,key0_n}),.actions(key_actions));
 function valid_edit;input[7:0]field;input[15:0]value;
 begin case(field)
  0,3,4,13,14,19:valid_edit=value<3;
  1,2,5,6,9:valid_edit=value<4;
  7,15,16,17,18,22,23,25,28:valid_edit=value<2;
  27:valid_edit=value<5;
  8:valid_edit=value<=256;
  10:valid_edit=value<256;
  11,12:valid_edit=value>=100 && value<=10000;
  20,21:valid_edit=value==1;
  default:valid_edit=0;
 endcase end endfunction
 reg local_write;reg[7:0]local_field;reg[15:0]local_value;
 wire apply_local=menu_write || local_write;
 wire[7:0]edit_field=menu_write ? {3'b0,menu_field} : local_field;
 wire[15:0]edit_value=menu_write ? menu_value : local_value;
 reg[255:0]local_display;
 always @*begin
  local_display=0;local_display[1:0]=operating_mode;local_display[3:2]=menu_page;
  local_display[8:4]=menu_field;local_display[9]=menu_editing;local_display[10]=running;local_display[12:11]=online;
  local_display[31:16]=menu_current;local_display[33:32]=lesson_song;local_display[47:40]=lesson_position;
  local_display[48]=lesson_hand;local_display[52:49]=lesson_zone;local_display[63:56]=lesson_note;
  local_display[79:64]=lesson_correct;local_display[95:80]=lesson_wrong;local_display[101:96]=presets;
  local_display[107:104]=profiles;local_display[115:112]={octave_right,octave_left};local_display[128:120]=test_gain;
  local_display[151:136]=hold_ms_left;local_display[167:152]=hold_ms_right;local_display[171:168]=release_ids;
  local_display[183:176]=wet;local_display[185:184]=effect_mode;local_display[188]=chord;local_display[189]=lesson_finished;
  local_display[190]=ui_hand;local_display[193:191]=ui_level;local_display[196:194]=ui_group;local_display[200:197]=ui_item;
  local_display[201]=lesson_mouse;local_display[203:202]=lesson_phase;local_display[204]=feedback_hand;local_display[208:205]=feedback_zone;
  local_display[224:209]=lesson_serial;local_display[232:225]=ui_notice;local_display[234:233]=calibration_result;
 end
 always @*begin
  menu_current=0;
  case(menu_field)
   0:menu_current=operating_mode;1:menu_current=presets[2:0];2:menu_current=presets[5:3];
   3:menu_current=profiles[1:0];4:menu_current=profiles[3:2];5:menu_current=octave_left;6:menu_current=octave_right;
   7:menu_current=chord;8:menu_current=test_gain;9:menu_current=effect_mode;10:menu_current=wet;
   11:menu_current=hold_ms_left;12:menu_current=hold_ms_right;13:menu_current=release_ids[1:0];14:menu_current=release_ids[3:2];
   15:menu_current=expression_config[39:32]!=0;16:menu_current=expression_config[103:96]!=0;
   17:menu_current=expression_config[63:40]!=0;18:menu_current=expression_config[127:104]!=0;
   19:menu_current=lesson_song;23:menu_current=lesson_mouse;default:menu_current=running;
  endcase
 end
 reg[15:0]seen_ui_serial,seen_lesson_serial;reg[1:0]seen_phase;reg[4:0]seen_position;
 reg response_pending;reg[7:0]response_kind,response_code;reg[15:0]response_seq;
 reg config_wait;reg[159:0]pending_config;reg[3:0]config_delay;
 reg strike_wait;reg[79:0]pending_strike;reg[15:0]strike_seq;
 reg cap_active,cap_ready,cap_armed,cap_wait_render,cap_start_on_pcm;
 reg[10:0]cap_wr;reg[15:0]cap_points,cap_id,upload_offset;
 reg[31:0]cap_event,cap_tick;reg cap_hand;reg meta_pending;
 reg[15:0]cap_revision;
 reg cap_sine_mode;reg[31:0]cap_sine_frequency;reg[15:0]cap_sine_amplitude;reg[1:0]cap_sine_channels;
 reg[143:0]capture_mem[0:2047];reg[143:0]cap_word;
 reg signed[15:0]held_dry_left,held_dry_right;
 wire signed[16:0]pcm_sum=$signed({pcm_left[15],pcm_left})+$signed({pcm_right[15],pcm_right});
 wire signed[15:0]pcm_mean=pcm_sum>>>1;
 wire[143:0]capture_word={held_voices,pcm_mean,pcm_right,pcm_left,(sine_mode ? sine_right : held_dry_right),(sine_mode ? sine_left : held_dry_left)};
 wire begin_capture=cap_start_on_pcm || (sine_mode && cap_wait_render);
 wire cap_busy=cap_active || cap_ready || cap_armed || cap_wait_render || cap_start_on_pcm;
 reg[31:0]status_timer;reg status_pending;
 reg[7:0]active_count;reg[511:0]hand_status;integer i;
 always @*begin
  active_count=0;hand_status=use_host ? 512'b0 : sensor_status;
  for(i=0;i<32;i=i+1)active_count=active_count+active[i];
  for(i=0;i<2;i=i+1)if(use_host)begin
   hand_status[i*256+0]=running;hand_status[i*256+1]=running;hand_status[i*256+3]=running;
   hand_status[i*256+4]=selected_valid[i];hand_status[i*256+7]=running;hand_status[i*256+8+:2]=3;
   hand_status[i*256+18+:4]=selected_zone[i*4+:4];hand_status[i*256+22+:4]=hit_zone[i*4+:4];
   hand_status[i*256+26+:2]=hit_profile[i*2+:2];hand_status[i*256+128+:32]=i==0 ? hits0 : hits1;
  end
 end
 wire[799:0]display_status={presets,1'b1,5'b0,wet,active_effect,effect_mode,8'b0,
  fx_drops,96'b0,actual_wet,drops[31:0],underflows,stereo_clips,active_count,
  1'b0,1'b0,chord,!running,1'b0,last_hand,{2{running}},presets[4:3],presets[1:0],profiles,hand_status};
 video_duo_hdmi display(.clk50(core_clk),.pixel_clk_in(pixel_clk),.serial_clk_in(serial_clk),.pll_lock_in(pll_lock),.menu_status(local_display),.rst_n(rst_n),.performance_status(display_status),
  .tmds_clk_p(tmds_clk_p_0),.tmds_clk_n(tmds_clk_n_0),.tmds_d_p(tmds_d_p_0),.tmds_d_n(tmds_d_n_0));
 reg[2047:0]status_bytes,saved_status;reg[511:0]info_bytes;
 always @*begin
  status_bytes=0;
  status_bytes[7:0]=7;status_bytes[1799:1792]=operating_mode;status_bytes[1807:1800]=menu_page;status_bytes[1815:1808]=menu_field;status_bytes[1823:1816]=menu_editing;status_bytes[1831:1824]=lesson_song;status_bytes[1839:1832]=lesson_position;status_bytes[1847:1840]=lesson_hand;status_bytes[1855:1848]=lesson_note;status_bytes[1871:1856]=lesson_correct;status_bytes[1887:1872]=lesson_wrong;status_bytes[1895:1888]=online;status_bytes[1903:1896]={4'b0,octave_right,octave_left};status_bytes[1791:1664]=expression_config;status_bytes[15:8]=running;status_bytes[23:16]=config_wait;status_bytes[31:24]=stop_reason;
  status_bytes[39:32]=profiles[1:0];status_bytes[47:40]=profiles[3:2];status_bytes[55:48]=presets[2:0];status_bytes[63:56]=presets[5:3];
  status_bytes[71:64]=chord;status_bytes[79:72]=effect_mode;status_bytes[87:80]=wet;status_bytes[95:88]=test_gain[7:0];
  status_bytes[103:96]=use_host ? {selected_valid[0],3'b0,selected_zone[3:0]} : {sensor_status[4],3'b0,sensor_status[21:18]};status_bytes[111:104]=use_host ? {selected_valid[1],3'b0,selected_zone[7:4]} : {sensor_status[260],3'b0,sensor_status[277:274]};
  status_bytes[119:112]=use_host ? hit_zone[3:0] : sensor_status[25:22];status_bytes[127:120]=use_host ? hit_zone[7:4] : sensor_status[281:278];
  status_bytes[159:128]=use_host ? hits0 : sensor_status[159:128];status_bytes[191:160]=use_host ? hits1 : sensor_status[415:384];status_bytes[223:192]=last_event;
  status_bytes[231:224]=last_hand;status_bytes[239:232]=last_velocity;status_bytes[247:240]=active_effect;status_bytes[255:248]=actual_wet;
  status_bytes[287:256]=active;status_bytes[319:288]=gates;status_bytes[351:320]=stolen;status_bytes[383:352]=underflows;
  status_bytes[415:384]=stereo_clips+fx_clips;status_bytes[447:416]=fx_drops;status_bytes[479:448]=rx_errors;status_bytes[511:480]=drops[31:0]+drops[63:32];
  status_bytes[543:512]=cap_event;status_bytes[575:544]=skipped_captures;status_bytes[607:576]=owned;status_bytes[615:608]=cap_busy;
  status_bytes[623:616]=gain[7:0];status_bytes[631:624]={4'b0,imu_int_n,key1_n,key0_n};status_bytes[655:640]=config_revision;
  status_bytes[639:632]={6'b0,gain[8],test_gain[8]};
  status_bytes[1455:1440]=hold_ms_left;status_bytes[1471:1456]=hold_ms_right;status_bytes[1479:1472]={4'b0,release_ids};status_bytes[1487:1480]=pa_en;
  status_bytes[1495:1488]={6'b0,piano_hold};status_bytes[1511:1496]=piano_coefficients[15:0];status_bytes[1527:1512]=piano_coefficients[31:16];
  status_bytes[1543:1536]=sine_mode;status_bytes[1551:1544]=sine_enable;status_bytes[1583:1552]=sine_frequency;status_bytes[1599:1584]=sine_amplitude;
  status_bytes[1607:1600]=sine_channels;status_bytes[1615:1608]=monitor_count;status_bytes[1647:1616]=monitor_ids;status_bytes[1655:1648]=sine_active;
  for(i=0;i<32;i=i+1)begin status_bytes[672+i*8+:8]={1'b0,notes[i*7+:7]};status_bytes[928+i*16+:16]=envelopes[i*16+:16];end
  status_bytes[1927:1920]=ui_hand;status_bytes[1935:1928]=ui_level;status_bytes[1943:1936]=ui_group;
  status_bytes[1951:1944]=ui_item;status_bytes[1959:1952]=lesson_mouse;status_bytes[1967:1960]=lesson_phase;
  status_bytes[1975:1968]=feedback_hand;status_bytes[1983:1976]=feedback_zone;status_bytes[1999:1984]=lesson_serial;
  status_bytes[2007:2000]=ui_notice;status_bytes[2015:2008]=calibration_result;status_bytes[2023:2016]=lesson_finished;
  status_bytes[2031:2024]=!running;status_bytes[2047:2032]=ui_serial;
  info_bytes=0;info_bytes[15:0]=response_seq;info_bytes[47:16]=50000000;info_bytes[79:48]=48000;info_bytes[87:80]=32;info_bytes[103:88]=2048;
  info_bytes[111:104]=8'd68;
  info_bytes[119:112]=8'd85;
  info_bytes[127:120]=8'd79;
  info_bytes[135:128]=8'd48;
  info_bytes[143:136]=8'd52;
  info_bytes[151:144]=8'd45;
  info_bytes[159:152]=8'd76;
  info_bytes[167:160]=8'd73;
  info_bytes[175:168]=8'd86;
  info_bytes[183:176]=8'd69;
  info_bytes[191:184]=8'd32;
  info_bytes[199:192]=8'd50;
  info_bytes[207:200]=8'd46;
  // Preserve the 2.1 capability prefix consumed by the published host.
  info_bytes[215:208]=8'd49;
  info_bytes[223:216]=8'd43; // +
  info_bytes[231:224]=8'd73; // I
  info_bytes[239:232]=8'd79; // O
  info_bytes[247:240]=8'd50;
  info_bytes[255:248]=8'd50;

 end
 reg tx_start;reg[7:0]tx_kind,tx_payload,saved_code;reg[15:0]tx_len,saved_seq;
 reg[31:0]saved_tick;reg[511:0]saved_info;reg[127:0]saved_meta;
 wire[15:0]tx_addr;wire[7:0]tx_byte;wire tx_valid,tx_uart_ready,tx_busy,tx_done;
 reg[19:0]capture_gap;
 frame_tx transmitter(core_clk,rst_n,tx_start,tx_kind,tx_len,saved_tick,tx_addr,tx_payload,tx_byte,tx_valid,tx_uart_ready,tx_busy,tx_done);
 uart_tx #(.CLK_HZ(50000000)) tx(core_clk,rst_n,32'd921600,tx_byte,tx_valid,tx_uart_ready,pc_tx);
 // Maximum payload is 330 bytes. Keep constant division/modulo at the actual
 // nine-bit packet range, instead of synthesizing unsized 32-bit arithmetic.
 wire[8:0]voice_address=tx_addr[8:0]-9'd10;
 wire[8:0]voice_row=cap_monitor_count==1 ? voice_address>>1 : cap_monitor_count==2 ? voice_address>>2 : cap_monitor_count==3 ? voice_address/9'd6 : voice_address>>3;
 wire[2:0]voice_byte=cap_monitor_count==1 ? {2'b0,voice_address[0]} : cap_monitor_count==2 ? {1'b0,voice_address[1:0]} : cap_monitor_count==3 ? voice_address%9'd6 : voice_address[2:0];
 wire[3:0]bus_byte=voice_address%9'd10;
 wire[10:0]sample_index=upload_offset[10:0]+(tx_kind==138 ? voice_row : voice_address/9'd10);
 always @(posedge core_clk)cap_word<=capture_mem[sample_index[10:0]];
 always @*begin
  tx_payload=0;
  case(tx_kind)
   128:tx_payload=saved_info[tx_addr[5:0]*8+:8];
   129,134:case(tx_addr)0:tx_payload=saved_seq[7:0];1:tx_payload=saved_seq[15:8];2:tx_payload=saved_code;endcase
   136:tx_payload=saved_status[tx_addr[7:0]*8+:8];
   137:tx_payload=saved_meta[tx_addr[3:0]*8+:8];
   139:case(tx_addr)
    0:tx_payload=cap_id[7:0];1:tx_payload=cap_id[15:8];2:tx_payload=cap_monitor_count;
    3,4,5,6:tx_payload=cap_monitor_ids[(tx_addr-3)*8+:8];7:tx_payload=cap_sine_mode;
    8,9,10,11:tx_payload=cap_sine_frequency[(tx_addr-8)*8+:8];12:tx_payload=cap_sine_amplitude[7:0];13:tx_payload=cap_sine_amplitude[15:8];14:tx_payload=cap_sine_channels;
   endcase
   130,138:case(tx_addr)
    0:tx_payload=cap_id[7:0];1:tx_payload=cap_id[15:8];2:tx_payload=upload_offset[7:0];3:tx_payload=upload_offset[15:8];
    4:tx_payload=cap_points[7:0];5:tx_payload=cap_points[15:8];6:tx_payload=8'h80;7:tx_payload=8'hbb;8,9:tx_payload=0;
    default:tx_payload=tx_kind==138 ? cap_word[80+voice_byte*8+:8] : cap_word[bus_byte*8+:8];
   endcase
  endcase
 end
 function valid_zone;input[7:0]p,z;begin valid_zone=p<3 && z<(p==1 ? 5 : p==2 ? 12 : 7);end endfunction
 wire valid_monitor=cmd_len==5 && cmd_data[7:0]<=4 &&
  (cmd_data[7:0]<1 || cmd_data[15:8]<32) && (cmd_data[7:0]<2 || cmd_data[23:16]<32 && cmd_data[23:16]!=cmd_data[15:8]) &&
  (cmd_data[7:0]<3 || cmd_data[31:24]<32 && cmd_data[31:24]!=cmd_data[15:8] && cmd_data[31:24]!=cmd_data[23:16]) &&
  (cmd_data[7:0]<4 || cmd_data[39:32]<32 && cmd_data[39:32]!=cmd_data[15:8] && cmd_data[39:32]!=cmd_data[23:16] && cmd_data[39:32]!=cmd_data[31:24]);
 wire valid_sine=cmd_len==8 && cmd_data[7:0]==1 && cmd_data[39:8]>=1789570 && cmd_data[39:8]<=894784853 &&
  cmd_data[55:40]>=33 && cmd_data[55:40]<=16423 && cmd_data[63:56]>=1 && cmd_data[63:56]<=3;
 wire strike_hand=cmd_data[32];
 wire valid_config=(cmd_len==9 || cmd_len==15 || cmd_len==20) && cmd_data[7:0]<2 && cmd_data[15:8]<3 && cmd_data[23:16]<3 && cmd_data[31:24]<4 && cmd_data[39:32]<4 && cmd_data[47:40]<2 && cmd_data[55:48]<4 &&
  (cmd_len==9 ? cmd_data[71:64]<=64 : cmd_data[79:64]<=256 && cmd_data[95:80]>=100 && cmd_data[95:80]<=10000 && cmd_data[111:96]>=100 && cmd_data[111:96]<=10000 && cmd_data[119:112]<16 && cmd_data[113:112]<3 && cmd_data[115:114]<3) &&
  (cmd_len!=20 || cmd_data[127:120]<4 && cmd_data[143:128]>=27 && cmd_data[143:128]<=4025 && cmd_data[159:144]>=27 && cmd_data[159:144]<=4025);
 wire valid_strike=cmd_len==10 && cmd_data[39:32]<2 && valid_zone(cmd_data[55:48],cmd_data[47:40]) &&
  (cmd_data[63:56]<2 || cmd_data[63:56]>=254) && cmd_data[71:64]>0 && cmd_data[71:64]<128 && cmd_data[79:72]<2;
 performance_controls #(.LONG_MS(800)) encoder(.clk(core_clk),.rst_n(rst_n),.enabled(1'b1),.encoder_a(encoder_a),.encoder_b(encoder_b),.encoder_button_n(encoder_button_n),.pedal_n(1'b1),.wrist_button_n(2'b11),.encoder_step(local_step),.encoder_direction(local_direction),.encoder_short(local_short),.encoder_long(local_long),.pedal_toggle(unused_pedal),.wrist_short(wrist_short),.wrist_long(wrist_long),.button_ready(buttons_ready),.invalid_transitions(encoder_errors));
 duo04_menu menu(.clk(core_clk),.rst_n(rst_n),.step(local_step),.direction(local_direction),.short_press(local_short),.long_press(local_long),
 .keys(key_actions),.remote_valid(remote_ui),.remote_action(cmd_data[3:0]),.running(running),.mode(operating_mode),.teaching_active(operating_mode==2),.finished(lesson_finished),
 .profiles(profiles),.presets(presets),.volume(test_gain),.current_value(menu_current),.page(menu_page),.field(menu_field),.editing(menu_editing),
 .write(menu_write),.value(menu_value),.active_hand(ui_hand),.level(ui_level),.group_id(ui_group),.item(ui_item),.stop(ui_stop),.notice(ui_notice),.serial(ui_serial));
 two_hand_i2c_core sensors(.clk(core_clk),.rst_n(rst_n),.enabled({2{!use_host && !config_wait}}),.force_reset(sensor_force_reset),.calibrate(calibrate),.express(2'b11),.mirror(2'b00),.layout_profile(operating_mode==2 ? 4'b0 : profiles),.scl_in(imu_scl),.sda_in(imu_sda),.int_n(imu_int_n),.scl_low(scl_low),.sda_low(sda_low),.reset_low(reset_low),.online(online),.status(sensor_status),.report_rates(sensor_rates),.processing_overruns(sensor_overruns),.event_valid(sensor_valid),.event_ready(sensor_ready),.event_data(sensor_events),.release_pending(sensor_release),.release_ack(sensor_ack),.epochs(sensor_epochs),.event_drops(sensor_drops),.cancelled_events(sensor_cancelled));
 dual_note_map lesson_map(.profile(events[24:23]),.zone(events[28:25]),.octave(events[22:21]),.chord(1'b0),.member(2'b00),.valid(mapped_valid),.midi_note(played_note));
 duo04_lesson lesson(.clk(core_clk),.rst_n(rst_n),.enabled(running && operating_mode==2),.restart(lesson_restart),.clear_feedback(lesson_clear),.song(lesson_song),
 .hit(event_valid && event_ready && events[31:30]==0 && mapped_valid),.hand(events[29]),.note(played_note),.zone(events[28:25]),
 .position(lesson_position),.correct(lesson_correct),.wrong(lesson_wrong),.target_hand(lesson_hand),.target_note(lesson_note),.target_zone(lesson_zone),
 .finished(lesson_finished),.last_correct(lesson_feedback),.feedback(lesson_phase),.feedback_hand(feedback_hand),.feedback_zone(feedback_zone),.event_serial(lesson_serial));
 always @(posedge core_clk)begin
  if(!rst_n)begin
   lesson_clear<=0;lesson_mouse<=0;lesson_saved<=0;saved_profiles<=0;saved_octaves<=0;saved_chord<=0;sensor_force_reset<=0;calibration_result<=0;calibration_mask<=0;calibration_age<=0;calibration_seen<=0;
   seen_ui_serial<=0;seen_lesson_serial<=0;seen_phase<=0;seen_position<=0;ticks<=0;link_age<=0;local_write<=0;local_field<=0;local_value<=0;operating_mode<=0;octave_left<=0;octave_right<=0;lesson_song<=0;lesson_restart<=0;calibrate<=0;running<=0;stop_reason<=0;profiles<=0;presets<=0;chord<=0;effect_mode<=0;wet<=128;test_gain<=8;
   hold_ms_left<=1500;hold_ms_right<=1500;hold_samples_left<=72000;hold_samples_right<=72000;release_ids<=5;
   expression_config<=0;sine_enable<=0;sine_mode<=0;sine_frequency<=89478485;sine_amplitude<=1036;sine_channels<=3;
   monitor_count<=2;monitor_ids<=32'hffff1000;cap_monitor_count<=2;cap_monitor_ids<=32'hffff1000;
   held_voices<=0;upload_voice<=0;voice_meta_pending<=0;cap_sine_mode<=0;cap_sine_frequency<=0;cap_sine_amplitude<=0;cap_sine_channels<=0;
   piano_hold<=0;piano_coefficients<={16'd134,16'd134};
   selected_valid<=0;selected_zone<=0;hit_zone<=0;hit_profile<=0;hits0<=0;hits1<=0;last_event<=0;last_hand<=0;last_velocity<=0;skipped_captures<=0;config_revision<=0;
   push<=0;cancel<=0;push_data<=0;clear_history<=0;response_pending<=0;response_kind<=129;response_code<=0;response_seq<=0;
   config_wait<=0;pending_config<=0;config_delay<=0;strike_wait<=0;pending_strike<=0;strike_seq<=0;
   cap_active<=0;cap_ready<=0;cap_armed<=0;cap_wait_render<=0;cap_start_on_pcm<=0;cap_wr<=0;cap_points<=512;cap_id<=0;upload_offset<=0;cap_event<=0;cap_tick<=0;cap_hand<=0;meta_pending<=0;cap_revision<=0;
   held_dry_left<=0;held_dry_right<=0;status_timer<=0;status_pending<=0;
   tx_start<=0;tx_kind<=0;tx_len<=0;saved_seq<=0;saved_code<=0;saved_tick<=0;saved_info<=0;saved_status<=0;saved_meta<=0;capture_gap<=0;
  end else begin
   if(sine_mode && !sine_enable && !sine_active)sine_mode<=0;
   sensor_force_reset<=0;
   if(calibration_mask!=0)begin
    if(calibration_age<250000000)calibration_age<=calibration_age+1'b1;
    if((calibration_mask[0] && sensor_status[2]) || (calibration_mask[1] && sensor_status[258]))calibration_seen<=1;
    if((online & calibration_mask)!=calibration_mask || calibration_age>=249999999)begin calibration_mask<=0;calibration_result<=3;end
    else if(calibration_seen && (!calibration_mask[0] || sensor_status[1] && !sensor_status[2]) && (!calibration_mask[1] || sensor_status[257] && !sensor_status[258]))begin calibration_mask<=0;calibration_result<=2;end
   end
   lesson_clear<=0;ticks<=ticks+1'b1;push<=0;cancel<=0;clear_history<=0;lesson_restart<=0;calibrate<=0;local_write<=local_write && menu_write;tx_start<=0;
   if(link_age<WATCHDOG_CYCLES)link_age<=link_age+1'b1;
   if(capture_gap!=0)capture_gap<=capture_gap-1'b1;
   if(ui_serial!=seen_ui_serial || lesson_serial!=seen_lesson_serial || lesson_phase!=seen_phase || lesson_position!=seen_position)begin
    seen_ui_serial<=ui_serial;seen_lesson_serial<=lesson_serial;seen_phase<=lesson_phase;seen_position<=lesson_position;status_pending<=1;
   end
   if(status_timer==4999999)begin status_timer<=0;status_pending<=1;end else status_timer<=status_timer+1'b1;
   if(config_wait)begin
    if(config_delay<15)config_delay<=config_delay+1'b1;
    if(config_delay>=4 && release_pending==0 && active==0)begin
     running<=pending_config[0];profiles<={pending_config[17:16],pending_config[9:8]};presets<={pending_config[34:32],pending_config[26:24]};
     chord<=pending_config[40];effect_mode<=pending_config[49:48];wet<=pending_config[63:56];test_gain<=pending_config[72:64];
     hold_ms_left<=pending_config[95:80];hold_ms_right<=pending_config[111:96];release_ids<=pending_config[115:112];
     hold_samples_left<=pending_config[95:80]*32'd48;hold_samples_right<=pending_config[111:96]*32'd48;
     piano_hold<=pending_config[121:120];piano_coefficients<=pending_config[159:128];
     config_revision<=config_revision+1'b1;config_wait<=0;stop_reason<=0;response_pending<=1;response_code<=0;response_kind<=129;status_pending<=1;
    end
   end
   if(strike_wait)begin
    strike_wait<=0;response_seq<=strike_seq;response_pending<=1;response_kind<=129;
    if(accepted[pending_strike[32]])begin
     response_code<=0;last_event<=pending_strike[31:0];last_hand<=pending_strike[32];last_velocity<=pending_strike[70:64];
     hit_zone[pending_strike[32]*4+:4]<=pending_strike[43:40];hit_profile[pending_strike[32]*2+:2]<=pending_strike[49:48];
     if(pending_strike[32])hits1<=hits1+1'b1;else hits0<=hits0+1'b1;
     if(pending_strike[72])begin
      if(!cap_busy)begin cap_monitor_count<=sine_mode ? 0 : monitor_count;cap_monitor_ids<=monitor_ids;cap_sine_mode<=sine_mode;cap_sine_frequency<=sine_frequency;cap_sine_amplitude<=sine_amplitude;cap_sine_channels<=sine_channels;cap_armed<=1;cap_event<=pending_strike[31:0];cap_hand<=pending_strike[32];cap_points<=512;cap_revision<=config_revision;end
      else skipped_captures<=skipped_captures+1'b1;
     end
    end else response_code<=3;
    status_pending<=1;
   end
   if(cap_armed && committed && committed_id==cap_event[7:0] && committed_hand==cap_hand)begin cap_armed<=0;cap_wait_render<=1;end
   if(input_accepted && !sine_mode)begin
    held_voices<={voice_samples[cap_monitor_ids[28:24]*16+:16],voice_samples[cap_monitor_ids[20:16]*16+:16],voice_samples[cap_monitor_ids[12:8]*16+:16],voice_samples[cap_monitor_ids[4:0]*16+:16]};
    held_dry_left<=dry_left;held_dry_right<=dry_right;
    if(cap_wait_render)begin cap_wait_render<=0;cap_start_on_pcm<=1;end
   end
   if(pcm_valid && (cap_active || begin_capture))begin
    capture_mem[begin_capture ? 11'd0 : cap_wr]<=capture_word;
    if(begin_capture)begin
     cap_wait_render<=0;
     cap_start_on_pcm<=0;cap_active<=1;cap_wr<=1;cap_tick<=ticks;cap_id<=cap_id+1'b1;
    end else begin
     if({5'b0,cap_wr}==cap_points-1'b1)begin cap_active<=0;cap_ready<=1;upload_offset<=0;meta_pending<=1;end
     else cap_wr<=cap_wr+1'b1;
    end
   end
   if(cmd_done)begin
    link_age<=0;response_seq<=cmd_seq;response_kind<=129;response_code<=0;response_pending<=1;
    case(cmd)
     1:begin response_kind<=128;if(use_host)begin sine_enable<=0;voice_meta_pending<=0;upload_voice<=0;running<=0;cancel<=3;clear_history<=3;selected_valid<=0;stop_reason<=0;cap_armed<=0;cap_wait_render<=0;cap_active<=0;cap_ready<=0;meta_pending<=0;cap_start_on_pcm<=0;config_wait<=0;end end
     20:response_kind<=134;
     21:if(cmd_len!=1 || cmd_data[7:0]!=0)response_code<=2;
     17:if((cmd_len!=1 && cmd_len!=3) || cmd_data[7:0]!=0 || (cmd_len==3 && cmd_data[23:8]!=512 && cmd_data[23:8]!=2048))response_code<=2;
        else if(cap_busy)response_code<=1;
        else begin cap_monitor_count<=sine_mode ? 0 : monitor_count;cap_monitor_ids<=monitor_ids;cap_sine_mode<=sine_mode;cap_sine_frequency<=sine_frequency;cap_sine_amplitude<=sine_amplitude;cap_sine_channels<=sine_channels;cap_wait_render<=1;cap_event<=0;cap_points<=cmd_len==3 ? cmd_data[23:8] : 2048;cap_revision<=config_revision;end
     48:if(operating_mode!=1 || !valid_config)response_code<=2;
        else if(config_wait || sine_active)response_code<=1;
        else begin
         config_wait<=1;config_delay<=0;pending_config<=cmd_len==20 ? cmd_data[159:0] : {16'd134,16'd134,8'd0,(cmd_len==15 ? cmd_data[119:0] : {8'h05,16'd1500,16'd1500,8'd0,cmd_data[71:0]})};cancel<=3;clear_history<=3;running<=0;selected_valid<=0;
         response_pending<=0;cap_armed<=0;cap_wait_render<=0;
        end
     49:if(cmd_len!=3 || cmd_data[7:0]>1 || cmd_data[15:8]>1 || (cmd_data[8] && !valid_zone({6'b0,profiles[cmd_data[0]*2+:2]},cmd_data[23:16])))response_code<=2;
        else begin selected_valid[cmd_data[0]]<=cmd_data[8];selected_zone[cmd_data[0]*4+:4]<=cmd_data[19:16];status_pending<=1;end
     50:if(!valid_strike)response_code<=2;
        else if(!use_host || !running || config_wait || release_pending[strike_hand] || cmd_data[49:48]!=profiles[strike_hand*2+:2] || (operating_mode==2 && cmd_data[63:56]!=0))response_code<=3;
        else begin
         push[strike_hand]<=1;push_data[strike_hand*32+:32]<={2'b0,strike_hand,cmd_data[43:40],cmd_data[49:48],cmd_data[57:56],cmd_data[70:64],2'b0,cmd_data[7:0],4'b0};
         pending_strike<=cmd_data[79:0];strike_seq<=cmd_seq;strike_wait<=1;response_pending<=0;
        end
     51:begin lesson_clear<=1;sine_enable<=0;running<=0;cancel<=3;clear_history<=3;selected_valid<=0;stop_reason<=1;config_wait<=0;cap_armed<=0;cap_wait_render<=0;status_pending<=1;end
     52:status_pending<=1;
     53:begin end
     54:if(!valid_monitor)response_code<=2;
        else begin monitor_count<=cmd_data[2:0];monitor_ids<=cmd_data[39:8];status_pending<=1;end
     55:if(!valid_sine)response_code<=2;
        else if(running || config_wait || gain!=0 || release_pending!=0 || active!=0 || sine_active)response_code<=1;
        else begin sine_mode<=1;sine_enable<=1;sine_frequency<=cmd_data[39:8];sine_amplitude<=cmd_data[55:40];sine_channels<=cmd_data[57:56];
         running<=0;cancel<=3;clear_history<=3;selected_valid<=0;stop_reason<=0;config_revision<=config_revision+1'b1;status_pending<=1;end
     57:if(cmd_len!=16 || cmd_data[39:32]>100 || cmd_data[103:96]>100 ||
          cmd_data[31:0]>1073742 || cmd_data[95:64]>1073742 ||
          (cmd_data[39:32]!=0 && cmd_data[31:0]<8948) || (cmd_data[103:96]!=0 && cmd_data[95:64]<8948) ||
          (cmd_data[63:40]!=0 && (cmd_data[63:40]<175 || cmd_data[63:40]>34953)) ||
          (cmd_data[127:104]!=0 && (cmd_data[127:104]<175 || cmd_data[127:104]>34953)))response_code<=2;
        else begin expression_config<=cmd_data[127:0];status_pending<=1;end
     56:if(cmd_len!=0)response_code<=2;else begin sine_enable<=0;running<=0;cancel<=3;clear_history<=3;stop_reason<=1;status_pending<=1;end
     61:if(cmd_len!=1 || cmd_data[7:0]>=12)response_code<=2;else if(cmd_data[7:0]!=11 && (local_step || local_short || local_long || key_actions!=0))response_code<=1;else status_pending<=1;
     62:if(cmd_len!=2 || cmd_data[7:0]>1 || cmd_data[15:8]>2 || menu_write || local_write)response_code<=2;
        else begin
         if(operating_mode!=2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;end
         operating_mode<=2;profiles<=0;octave_left<=0;octave_right<=0;chord<=0;sine_enable<=0;sine_mode<=0;
         lesson_mouse<=cmd_data[0];lesson_song<=cmd_data[9:8];running<=0;cancel<=3;clear_history<=3;lesson_restart<=1;status_pending<=1;config_revision<=config_revision+1'b1;end
     63:if(cmd_len!=1 || cmd_data[7:0]>4 || local_write || menu_write)response_code<=2;
        else begin local_write<=1;local_field<=27;local_value<={8'b0,cmd_data[7:0]};end
     60:if(cmd_len!=3 || !valid_edit(cmd_data[7:0],cmd_data[23:8]))response_code<=2;
        else if(local_write || menu_write || (operating_mode==2 && (cmd_data[7:0]==3 || cmd_data[7:0]==4 || cmd_data[7:0]==5 || cmd_data[7:0]==6 || cmd_data[7:0]==7)))response_code<=1;
        else begin local_write<=1;local_field<=cmd_data[7:0];local_value<=cmd_data[23:8];end
     default:response_code<=2;
    endcase
   end
   // Offline playing needs no PC; the PC-controlled calibration source always
   // keeps the communication watchdog, even when entered from offline mode.
   if(key_stop || (((use_host && running) || sine_enable) && link_age>=WATCHDOG_CYCLES-1))begin
    sine_enable<=0;running<=0;cancel<=3;clear_history<=3;selected_valid<=0;config_wait<=0;cap_armed<=0;cap_wait_render<=0;
    if(key_stop || use_host)lesson_clear<=1;stop_reason<=key_stop ? 3 : 2;status_pending<=1;
   end
   if(apply_local && !key_stop)begin
    status_pending<=1;config_revision<=config_revision+1'b1;
    case(edit_field)
     0:if(edit_value<3)begin
      if(operating_mode!=2 && edit_value==2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;profiles<=0;octave_left<=0;octave_right<=0;chord<=0;end
      else if(operating_mode==2 && edit_value!=2 && lesson_saved)begin profiles<=saved_profiles;octave_left<=saved_octaves[1:0];octave_right<=saved_octaves[3:2];chord<=saved_chord;lesson_saved<=0;end
      operating_mode<=edit_value[1:0];running<=0;cancel<=3;clear_history<=3;sine_enable<=0;sine_mode<=0;lesson_restart<=1;cap_armed<=0;cap_wait_render<=0;end
     1:if(edit_value<4)presets[2:0]<=edit_value[2:0];
     2:if(edit_value<4)presets[5:3]<=edit_value[2:0];
     3:if(edit_value<3)profiles[1:0]<=edit_value[1:0];
     4:if(edit_value<3)profiles[3:2]<=edit_value[1:0];
     5:if(edit_value<4)octave_left<=edit_value[1:0];
     6:if(edit_value<4)octave_right<=edit_value[1:0];
     7:chord<=edit_value[0];8:if(edit_value<=256)test_gain<=edit_value[8:0];
     9:if(edit_value<4)effect_mode<=edit_value[1:0];10:if(edit_value<256)wet<=edit_value[7:0];
     11:if(edit_value>=100 && edit_value<=10000)begin hold_ms_left<=edit_value;hold_samples_left<=edit_value*32'd48;end
     12:if(edit_value>=100 && edit_value<=10000)begin hold_ms_right<=edit_value;hold_samples_right<=edit_value*32'd48;end
     13:if(edit_value<3)release_ids[1:0]<=edit_value[1:0];14:if(edit_value<3)release_ids[3:2]<=edit_value[1:0];
     15:begin expression_config[31:0]<=32'd492132;expression_config[39:32]<=edit_value[0] ? 8'd20 : 8'd0;end
     16:begin expression_config[95:64]<=32'd492132;expression_config[103:96]<=edit_value[0] ? 8'd20 : 8'd0;end
     17:expression_config[63:40]<=edit_value[0] ? 24'd2330 : 24'd0;
     18:expression_config[127:104]<=edit_value[0] ? 24'd2330 : 24'd0;
     19:if(edit_value<3)begin lesson_song<=edit_value[1:0];lesson_restart<=1;running<=0;cancel<=3;clear_history<=3;end
     20:begin if(operating_mode!=2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;end operating_mode<=2;octave_left<=0;octave_right<=0;running<=1;lesson_restart<=1;cancel<=3;clear_history<=3;profiles<=0;chord<=0;sine_mode<=0;sine_enable<=0;end
     21:begin calibrate<=3;calibration_mask<=3;calibration_age<=0;calibration_seen<=0;calibration_result<=1;end
     23:begin lesson_mouse<=edit_value[0];running<=0;cancel<=3;clear_history<=3;lesson_restart<=1;end
     25:begin calibrate<=edit_value[0] ? 2 : 1;calibration_mask<=edit_value[0] ? 2 : 1;calibration_age<=0;calibration_seen<=0;calibration_result<=1;end
     28:begin sensor_force_reset<=edit_value[0] ? 2 : 1;cancel<=edit_value[0] ? 2 : 1;end
     27:begin
      if(edit_value==0 || edit_value==2)begin stop_reason<=edit_value==0 ? 1 : 6;if(edit_value==0)lesson_clear<=1;running<=0;cancel<=3;clear_history<=3;end
      else if(edit_value==3)begin if(operating_mode==2 && !lesson_finished)begin running<=1;stop_reason<=0;end end
      else begin
       if(operating_mode!=2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;end
       operating_mode<=2;profiles<=0;octave_left<=0;octave_right<=0;chord<=0;running<=1;stop_reason<=0;lesson_restart<=1;cancel<=3;clear_history<=3;sine_enable<=0;sine_mode<=0;
      end
     end
     22:begin stop_reason<=edit_value[0] ? 0 : (operating_mode==2 ? 6 : 1);running<=edit_value[0];if(!edit_value[0])begin cancel<=3;clear_history<=3;end end
    endcase
   end
   if(operating_mode==2 && !lesson_mouse && running && !online[lesson_hand])begin running<=0;cancel<=3;clear_history<=3;stop_reason<=5;status_pending<=1;end
   if(key_stop)begin lesson_clear<=1;running<=0;sine_enable<=0;cancel<=3;clear_history<=3;config_wait<=0;local_write<=0;selected_valid<=0;cap_armed<=0;cap_wait_render<=0;stop_reason<=3;status_pending<=1;end
   if(!tx_busy && !tx_start && !tx_done)begin
    saved_tick<=ticks;
    if(response_pending)begin
     saved_seq<=response_seq;saved_code<=response_code;saved_info<=info_bytes;tx_kind<=response_kind;tx_len<=response_kind==128 ? 32 : 3;
     tx_start<=1;response_pending<=0;
    end else if(meta_pending)begin
     saved_meta<={16'b0,8'd5,8'd1,cap_revision,cap_tick,cap_event,cap_id};tx_kind<=137;tx_len<=16;tx_start<=1;meta_pending<=0;voice_meta_pending<=1;upload_voice<=0;
    end else if(voice_meta_pending)begin tx_kind<=139;tx_len<=16;tx_start<=1;voice_meta_pending<=0;
    end else if(status_pending)begin saved_status<=status_bytes;tx_kind<=136;tx_len<=256;tx_start<=1;status_pending<=0;end
    else if(cap_ready && capture_gap==0)begin tx_kind<=upload_voice ? 138 : 130;tx_len<=upload_voice ? 10+cap_monitor_count*64 : 330;tx_start<=1;end
   end
   if(tx_done && (tx_kind==130 || tx_kind==138))begin
    capture_gap<=CAPTURE_GAP_CYCLES;
    if(tx_kind==130 && cap_monitor_count!=0)upload_voice<=1;
    else begin upload_voice<=0;if(upload_offset==cap_points-32)cap_ready<=0;else upload_offset<=upload_offset+32;end
   end
  end
 end
endmodule
