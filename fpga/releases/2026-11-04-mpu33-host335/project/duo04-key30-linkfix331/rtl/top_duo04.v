// DUO04: shared dual-IMU/offline, mouse and teaching instrument.
module top_duo04 #(parameter BOOT_CYCLES=524288, WATCHDOG_CYCLES=100000000, KEY_DEBOUNCE=1000000, CAPTURE_GAP_CYCLES=500000)(
 input clk,reset_key,key0_n,key1_n,key2_n,pc_rx,
 input encoder_a,encoder_b,encoder_button_n,input[1:0]wrist_button_n,input[1:0]wrist_button2_n,
 inout[1:0]imu_scl,imu_sda,
 output hp_bck,hp_ws,hp_din,pa_en,pc_tx,
 output i2s_bck,i2s_ws,i2s_dout,
 output tmds_clk_p_0,tmds_clk_n_0,output[2:0]tmds_d_p_0,tmds_d_n_0);
 wire core_clk,serial_clk,pixel_clk,pll_lock;
`ifdef TANG_SIM
 assign core_clk=clk;assign serial_clk=clk;assign pixel_clk=clk;assign pll_lock=1;
`else
 wire core_lock,screen_lock,unused125,unused25,unused49;
 wire reference_clock;
 IBUF reference_input(.I(clk),.O(reference_clock));
 duo04_pll main_pll(.clkin(reference_clock),.core_clk(core_clk),.clkout0(unused125),.clkout1(unused25),.lock(core_lock));
 screen_pll_245 screen_pll(.clkin(reference_clock),.core_clk(unused49),.clkout0(serial_clk),.clkout1(pixel_clk),.lock(screen_lock));
 assign pll_lock=core_lock && screen_lock;
`endif
 reg[2:0]core_reset_pipe=0;
 always @(posedge core_clk or negedge pll_lock)begin
  if(!pll_lock)core_reset_pipe<=0;else core_reset_pipe<={core_reset_pipe[1:0],1'b1};
 end
 wire[1:0]scl_low,sda_low,reset_low,online;
 genvar pad;generate for(pad=0;pad<2;pad=pad+1)begin:pads
  assign imu_scl[pad]=scl_low[pad] ? 1'b0 : 1'bz;
  assign imu_sda[pad]=sda_low[pad] ? 1'b0 : 1'bz;
 end endgenerate
 reg[19:0]boot=0;reg[1:0]reset_sync=0;
 always @(posedge core_clk)begin if(boot<BOOT_CYCLES)boot<=boot+1'b1;reset_sync<={reset_sync[0],reset_key};end
 wire rst_n=core_reset_pipe[2] && boot>=BOOT_CYCLES && !reset_sync[1];
 reg config_wait;
 reg[1:0]operating_mode;reg[1:0]octave_left,octave_right;reg[1:0]lesson_song;
 reg lesson_restart;reg[1:0]calibrate;
 wire local_step,local_direction,local_short,local_long;
 wire[11:0]key_actions;wire ui_stop,ui_hand;wire[2:0]ui_level,ui_group;wire[3:0]ui_item;wire[7:0]ui_notice;
 reg remote_ui;reg[3:0]remote_action_q;
 wire remote_stop;
 wire[15:0]ui_serial;reg lesson_clear;
 reg lesson_mouse,lesson_saved;reg[3:0]saved_profiles,saved_octaves;reg saved_chord;
 reg[1:0]sensor_force_reset;reg[1:0]calibration_result;reg[1:0]calibration_mask;reg[31:0]calibration_age;reg calibration_seen;
 // Mode changes cancel the old source before admitting a new source.
 // Register the source predicate to avoid decode+mux+epoch-compare+bank-write
 // on one high-fanout timing path. The one-clock transition stays muted.
 reg use_host,epoch_source;
 reg[63:0]selected_epochs;
 wire requested_host=operating_mode==1 || (operating_mode==2 && lesson_mouse);
 wire source_ready=use_host==requested_host && epoch_source==use_host;

 wire[1:0]lesson_phase;wire feedback_hand;wire[3:0]feedback_zone;wire[15:0]lesson_serial;
 // STOP bypasses the ordinary UI command pipeline and cancels queued edits.
 wire key_stop=key_actions[11] || ui_stop || remote_stop;
 wire[1:0]wrist_short,wrist_long;wire[3:0]buttons_ready;wire[15:0]encoder_errors;wire unused_pedal;

 wire[1:0]menu_page;wire[5:0]menu_field;wire menu_editing,menu_write;wire[15:0]menu_value;reg[15:0]menu_current;

 wire[1:0]sensor_release,sensor_ack,sensor_cancel_now;wire[63:0]sensor_epochs,sensor_events,sensor_drops,sensor_cancelled,sensor_overruns;wire[95:0]sensor_rates;wire[511:0]sensor_status;wire sensor_valid,sensor_ready;

 wire[11:0]lesson_position;wire[1:0]lesson_octave;wire[15:0]lesson_hold_ms;wire[31:0]lesson_hold_samples;wire lesson_target_ready;wire[15:0]lesson_correct,lesson_wrong;wire lesson_hand,lesson_finished,lesson_feedback;wire[3:0]lesson_zone;
 wire score_ack,score_busy,score_uploading,score_loaded,score_committed;wire[7:0]score_code;
 wire[31:0]score_transfer,score_crc,score_word,score_readback;wire[11:0]score_uploaded,score_total;
 wire[1:0]score_profile;wire[15:0]score_revision,score_read_revision;wire[10:0]score_address,score_read_index;
 reg[15:0]score_seq;reg[383:0]saved_score;reg score_status_pending;reg[22:0]score_timer;
 wire[6:0]lesson_note;wire lesson_hit,played_hand;wire[6:0]played_note;wire[3:0]played_zone;
 wire[63:0]legacy_mapped_sensor_events={sensor_events[63:23],(operating_mode==2 ? lesson_octave : (sensor_events[29] ? octave_right : octave_left)),sensor_events[20:0]};

 // GEST24 uses actual pose strobes, not status refresh timing.
 reg[1:0]lite_glide,lite_vibrato,test_pressed2;reg[8:0]lite_glide_ms;wire legato_taken;wire[1:0]button_event,combo_active;reg[31:0]key_count[0:1];integer kc;
wire[63:0]button_payload;
 always @(posedge core_clk)begin if(!rst_n)begin key_count[0]<=0;key_count[1]<=0;end else for(kc=0;kc<2;kc=kc+1)if(button_event[kc] && button_payload[kc*32+30+:2]==0)key_count[kc]<=key_count[kc]+1'b1;end
wire[1:0]lite_pending,lite_judging;reg[1:0]yaw_invert;reg[1:0]wrist_enable,wrist_invert,test_pressed;reg[31:0]test_pitch;
 reg[1:0]test_pose_valid;reg[31:0]test_pose_age[0:1];reg[17:0]test_pose_div;integer ta;
 wire[63:0]sensor_hit_snapshots;wire[3:0]sensor_hit_octaves;wire[1:0]sensor_hit_used;wire[1:0]sensor_pose_valid;wire[31:0]sensor_pitch;
 wire[1:0]gesture_enable=operating_mode==2 ? 2'b0 : 2'b11;
 wire[1:0]wrist_pressed,wrist_fresh;wire[3:0]wrist_octave,wrist_snapshot;
 wire[111:0]wrist_debug;wire[31:0]wrist_bend,wrist_serial;
 wire[63:0]mapped_sensor_events=sensor_events;



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
 wire[15:0]vibrato_depth={gesture_enable[1] ? 8'd0 : expression_config[103:96],gesture_enable[0] ? 8'd0 : expression_config[39:32]};
 wire[47:0]glide_steps=0;
 wire[39:0]vibrato_ratios;
 assign vibrato_ratios={20'd65536,20'd65536};

 reg sine_enable,sine_mode;reg[31:0]sine_frequency;reg[15:0]sine_amplitude;reg[1:0]sine_channels;
 wire sine_active=0,sine_valid=0;wire music_valid,music_off;wire signed[15:0]sine_left,sine_right,music_left,music_right;
 reg[2:0]monitor_count,cap_monitor_count;reg[31:0]monitor_ids,cap_monitor_ids;
 reg[63:0]held_voices;reg upload_voice,voice_meta_pending;
 wire[7:0]rx_byte;wire rx_valid;wire[31:0]rx_errors;
 uart_rx rx(.clk(core_clk),.rst_n(rst_n),.rx(pc_rx),.baud(32'd921600),.data(rx_byte),.valid(rx_valid),.start(),.error());
 wire cmd_done;wire[7:0]cmd;wire[15:0]cmd_seq;wire[6:0]cmd_len;wire[511:0]cmd_data;
 assign remote_stop=cmd_done && cmd==61 && cmd_len==1 && cmd_data[7:0]==11;
 always @(posedge core_clk)begin
  if(!rst_n)begin remote_ui<=0;remote_action_q<=0;end
  else begin
   remote_ui<=cmd_done && cmd==61 && cmd_len==1 && cmd_data[7:0]<12 &&
     (cmd_data[7:0]==11 || !(local_step || local_short || local_long || key_actions!=0));
   remote_action_q<=cmd_data[3:0];
  end
 end
 frame_rx commands(core_clk,rst_n,rx_byte,rx_valid,cmd_done,cmd,cmd_seq,cmd_len,cmd_data,rx_errors);
 reg[1:0]push,cancel,clear_history;reg[63:0]push_data;wire[1:0]accepted,release_pending,release_ack;
 wire[63:0]epochs,events,drops,cancelled;wire event_valid,event_ready;
 wire host_valid,host_ready;wire[63:0]host_events,host_epochs;wire[1:0]host_release;wire[1:0]host_ack;
 wire source_event_valid=running && source_ready && !score_uploading && (operating_mode!=2 || (lesson_target_ready && lesson_phase!=1)) && (use_host ? host_valid : sensor_valid);
 wire selected_ready;
 wire[63:0]raw_selected_events=use_host ? host_events : mapped_sensor_events;
 wire[63:0]selected_events=raw_selected_events;
 assign epochs=selected_epochs;
 event_register_slice event_stage(.clk(core_clk),.rst_n(rst_n),
  .flush(!running || !source_ready || key_stop || lesson_restart || config_wait || (operating_mode==2 && (!lesson_target_ready || lesson_phase==1))),
  .cancel(cancel | (use_host ? 2'b00 : sensor_cancel_now)),.epochs(epochs),
  .in_valid(source_event_valid),.in_ready(selected_ready),.in_data(selected_events),
  .out_valid(event_valid),.out_ready(event_ready),.out_data(events));
 assign release_pending=host_release | sensor_release;
 assign host_ack=release_ack;assign sensor_ack=release_ack;
 // Auto-starting a lesson may change mode and running together. Neither
 // source may consume a queued event during the one-clock selection change.
 assign host_ready=source_ready && use_host && (running && (operating_mode!=2 || (lesson_target_ready && lesson_phase!=1)) ? selected_ready : 1'b1);
 assign sensor_ready=source_ready && !use_host && (running && (operating_mode!=2 || (lesson_target_ready && lesson_phase!=1)) ? selected_ready : 1'b1);
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
  .hold_samples_left(operating_mode==2 && lesson_song==3 ? lesson_hold_samples : hold_samples_left),.hold_samples_right(operating_mode==2 && lesson_song==3 ? lesson_hold_samples : hold_samples_right),
  .legato_enable(combo_active & lite_glide & gesture_enable),.legato_taken(legato_taken),.wrist_enabled(gesture_enable),.wrist_pressed(wrist_pressed),.wrist_bend(wrist_bend),
  .piano_hold(piano_hold & ~gesture_enable),.piano_coefficients(piano_coefficients),
  .glide_coefficients(glide_steps),.vibrato_ratios(vibrato_ratios),.bend_cents({(use_host || gesture_enable[1]) ? 16'd0 : sensor_status[351:336],(use_host || gesture_enable[0]) ? 16'd0 : sensor_status[95:80]}),.vibrato_cents(32'b0),.brightness(use_host ? 16'h8080 : {sensor_status[375:368],sensor_status[119:112]}),.samples(samples),.sample_valid(sample_valid),
  .clips(clips),.underflows(underflows),.stereo_left(dry_left),.stereo_right(dry_right),.stereo_clips(stereo_clips),
  .owned(owned),.gates(gates),.active_voices(active),.notes(notes),.envelopes(envelopes),.voice_samples(),
  .invalid_events(invalid),.stolen_notes(stolen),.max_render_cycles(max_render),
  .monitor_voice(5'b0),.monitor_frequency(),.monitor_envelope(),.monitor_stage(),
  .committed(committed),.committed_id(committed_id),.committed_hand(committed_hand));
 reg output_mute;wire signed[15:0]pcm_left,pcm_right;wire pcm_valid,input_accepted;wire[1:0]active_effect;wire[7:0]actual_wet;wire[8:0]gain;
 wire[31:0]fx_drops,fx_clips;
 stereo_output_path #(.MAKEUP_SHIFT(3)) audio_path(.clk(core_clk),.rst_n(rst_n),.in_valid(sample_valid),.in_left(dry_left),.in_right(dry_right),
  .muted(!running),.test_gain(test_gain),.input_accepted(input_accepted),.requested_mode(effect_mode),.requested_wet(wet),.clear_history(clear_history),
  .pcm_left(music_left),.pcm_right(music_right),.pcm_valid(music_valid),.active_mode(active_effect),.actual_wet(actual_wet),
  .master_gain(gain),.amplifier_off(music_off),.fx_drops(fx_drops),.fx_clips(fx_clips));
 assign pcm_left=music_left;assign pcm_right=music_right;
 assign pcm_valid=music_valid;assign pa_en=music_off;
 stereo_serial_output dac(.clk(core_clk),.rst_n(rst_n),.pcm_left(output_mute ? 16'sd0 : pcm_left),.pcm_right(output_mute ? 16'sd0 : pcm_right),.bck(hp_bck),.ws(hp_ws),.dout(hp_din),.sample_tick(sample_tick),.i2s_bck(i2s_bck),.i2s_ws(i2s_ws),.i2s_dout(i2s_dout));

 duo04_keys keys(.clk(core_clk),.rst_n(rst_n),.key_n({key2_n,key1_n,key0_n}),.actions(key_actions));
 function valid_edit;input[7:0]field;input[15:0]value;
 begin case(field)
  0,3,4,13,14:valid_edit=value<3;
  19:valid_edit=value<4;
  1,2,5,6,9:valid_edit=value<4;
  7,15,16,17,18,22,23,25,28,29,30,31,32:valid_edit=value<2;
  27:valid_edit=value<5;
  8:valid_edit=value<=256;
  10:valid_edit=value<256;
  11,12:valid_edit=value>=100 && value<=10000;
  20,21:valid_edit=value==1;
  default:valid_edit=0;
 endcase end endfunction
 reg local_write;reg[7:0]local_field;reg[15:0]local_value;
 reg apply_local;reg[7:0]edit_field;reg[15:0]edit_value;
 // Separate menu source selection from the parameter-bank validation and
 // writes. STOP flushes this one-cycle queue; it can never replay an edit.
 always @(posedge core_clk)begin
  if(!rst_n || key_stop)begin apply_local<=0;edit_field<=0;edit_value<=0;end
  else begin
   apply_local<=menu_write || local_write;
   edit_field<=menu_write ? {2'b0,menu_field} : local_field;
   edit_value<=menu_write ? menu_value : local_value;
  end
 end
 reg[3:0]menu_expression_flags;
 always @(posedge core_clk)begin
  if(!rst_n)menu_expression_flags<=0;
  else menu_expression_flags<={lite_glide,lite_vibrato};
 end
 reg[287:0]local_display;
 always @*begin
  local_display=0;local_display[287:256]={score_total,lesson_position,6'b0,score_loaded,(lesson_song==3)};local_display[1:0]=operating_mode;local_display[3:2]=menu_page;
  local_display[8:4]=menu_field;local_display[9]=menu_editing;local_display[10]=running;local_display[12:11]=online;
  local_display[31:16]=menu_current;local_display[33:32]=lesson_song;local_display[47:40]=lesson_position;
  local_display[48]=lesson_hand;local_display[52:49]=lesson_zone;local_display[63:56]=lesson_note;
  local_display[79:64]=lesson_correct;local_display[95:80]=lesson_wrong;local_display[101:96]=presets;
  local_display[107:104]=profiles;local_display[115:112]=wrist_octave;local_display[128:120]=test_gain;
  local_display[151:136]=hold_ms_left;local_display[167:152]=hold_ms_right;local_display[171:168]=release_ids;
  local_display[183:176]=wet;local_display[185:184]=effect_mode;local_display[188]=chord;local_display[189]=lesson_finished;
  local_display[190]=ui_hand;local_display[193:191]=ui_level;local_display[196:194]=ui_group;local_display[200:197]=ui_item;
  local_display[201]=lesson_mouse;local_display[203:202]=lesson_phase;local_display[204]=feedback_hand;local_display[208:205]=feedback_zone;
  local_display[224:209]=lesson_serial;local_display[232:225]=ui_notice;local_display[234:233]=calibration_result;local_display[235]=menu_field[5];local_display[245:242]={wrist_debug[99:98],wrist_debug[43:42]};local_display[249:246]=wrist_snapshot;local_display[237:236]=wrist_pressed;local_display[241:238]=operating_mode==2 ? {lesson_octave,lesson_octave} : wrist_octave;
 end
 always @*begin
  menu_current=0;
  case(menu_field)
   0:menu_current=operating_mode;1:menu_current=presets[2:0];2:menu_current=presets[5:3];
   3:menu_current=profiles[1:0];4:menu_current=profiles[3:2];5:menu_current=octave_left;6:menu_current=octave_right;
   7:menu_current=chord;8:menu_current=test_gain;9:menu_current=effect_mode;10:menu_current=wet;
   11:menu_current=hold_ms_left;12:menu_current=hold_ms_right;13:menu_current=release_ids[1:0];14:menu_current=release_ids[3:2];
   15:menu_current=menu_expression_flags[0];16:menu_current=menu_expression_flags[1];
   17:menu_current=menu_expression_flags[2];18:menu_current=menu_expression_flags[3];
   29:menu_current=wrist_enable[0];30:menu_current=wrist_enable[1];31:menu_current=wrist_invert[0];32:menu_current=wrist_invert[1];
   19:menu_current=lesson_song;23:menu_current=lesson_mouse;default:menu_current=running;
  endcase
 end
 reg[15:0]seen_ui_serial,seen_lesson_serial;reg[1:0]seen_phase;reg[11:0]seen_position;
 wire score_command=cmd_done && cmd>=69 && cmd<=74;
 score_store scores(.clk(core_clk),.rst_n(rst_n),.abort(key_stop),.playing(running),.command(score_command),.kind(cmd),.length(cmd_len),.payload(cmd_data),
 .ack(score_ack),.code(score_code),.busy(score_busy),.uploading(score_uploading),.loaded(score_loaded),.committed(score_committed),
 .transfer_id(score_transfer),.active_crc(score_crc),.uploaded(score_uploaded),.total(score_total),.profile(score_profile),.revision(score_revision),
 .read_address(score_address),.read_word(score_word),.readback_index(score_read_index),.readback_word(score_readback),.readback_revision(score_read_revision));
 wire[3:0]teaching_profiles=lesson_song==3 ? {score_profile,score_profile} : 4'b0;
 wire score_lesson_ok=lesson_song!=3 || score_loaded;
 reg response_pending;reg[7:0]response_kind,response_code;reg[15:0]response_seq;
 reg[159:0]pending_config;reg[3:0]config_delay;
 reg strike_wait;reg[79:0]pending_strike;reg[15:0]strike_seq;
 reg cap_active,cap_ready,cap_armed,cap_wait_render,cap_start_on_pcm;
 reg[10:0]cap_wr;reg[15:0]cap_points,cap_id,upload_offset;
 reg[31:0]cap_event,cap_tick;reg cap_hand;reg meta_pending;
 reg[15:0]cap_revision;
 reg cap_sine_mode;reg[31:0]cap_sine_frequency;reg[15:0]cap_sine_amplitude;reg[1:0]cap_sine_channels;
 reg[79:0]capture_mem[0:2047];reg[79:0]cap_word;
 reg signed[15:0]held_dry_left,held_dry_right;
 wire signed[16:0]pcm_sum=$signed({pcm_left[15],pcm_left})+$signed({pcm_right[15],pcm_right});
 wire signed[15:0]pcm_mean=pcm_sum>>>1;
 wire[79:0]capture_word={pcm_mean,pcm_right,pcm_left,held_dry_right,held_dry_left};
 wire begin_capture=cap_start_on_pcm || (sine_mode && cap_wait_render);
 wire cap_busy=cap_active || cap_ready || cap_armed || cap_wait_render || cap_start_on_pcm;
 reg[31:0]event_drop_count;reg[1:0]event_pending;reg[255:0]event_mail[0:1],saved_event;
 reg[63:0]event_seen;reg[1:0]event_changed;integer eh;

 reg[31:0]status_timer;reg status_pending;reg[63:0]last_sensor_hits;
 reg[7:0]active_count;reg[511:0]hand_status;integer i;
 always @*begin
  active_count=0;hand_status=use_host ? 512'b0 : sensor_status;

  for(i=0;i<2;i=i+1)if(use_host)begin
   hand_status[i*256+0]=running;hand_status[i*256+1]=running;hand_status[i*256+3]=running;
   hand_status[i*256+4]=selected_valid[i];hand_status[i*256+7]=running;hand_status[i*256+8+:2]=3;
   hand_status[i*256+18+:4]=selected_zone[i*4+:4];hand_status[i*256+22+:4]=hit_zone[i*4+:4];
   hand_status[i*256+26+:2]=hit_profile[i*2+:2];hand_status[i*256+128+:32]=i==0 ? hits0 : hits1;
  end
  for(i=0;i<2;i=i+1)begin hand_status[i*256+48+:16]=use_host ? test_pitch[i*16+:16] : sensor_pitch[i*16+:16];hand_status[i*256+120+:8]=wrist_debug[i*56+44+:8];hand_status[i*256+128+:32]=key_count[i];hand_status[i*256+22+:4]=button_payload[i*32+25+:4];hand_status[i*256+26+:2]=button_payload[i*32+23+:2];end
 end
 wire[799:0]display_status={presets,1'b1,5'b0,wet,active_effect,effect_mode,8'b0,
  fx_drops,96'b0,actual_wet,drops[31:0],underflows,stereo_clips,active_count,
  1'b0,1'b0,chord,!running,1'b0,last_hand,{2{running}},presets[4:3],presets[1:0],profiles,hand_status};
 video_duo_hdmi display(.clk50(core_clk),.pixel_clk_in(pixel_clk),.serial_clk_in(serial_clk),.pll_lock_in(pll_lock),.menu_status(local_display),.rst_n(rst_n),.performance_status(display_status),
  .tmds_clk_p(tmds_clk_p_0),.tmds_clk_n(tmds_clk_n_0),.tmds_d_p(tmds_d_p_0),.tmds_d_n(tmds_d_n_0));
 wire[1535:0]sensor_diagnostic;reg[3967:0]status_bytes,saved_status;reg[511:0]info_bytes;
 always @*begin
  status_bytes=0;
  status_bytes[7:0]=10;status_bytes[2295:2288]={6'b0,yaw_invert};status_bytes[3839:2304]=sensor_diagnostic;status_bytes[3847:3840]=1;status_bytes[3855:3848]=output_mute;status_bytes[3967:3856]=wrist_debug;status_bytes[1799:1792]=operating_mode;status_bytes[1807:1800]=menu_page;status_bytes[1815:1808]=menu_field;status_bytes[1823:1816]=menu_editing;status_bytes[1831:1824]=lesson_song;status_bytes[1839:1832]=lesson_position>255 ? 8'd255 : lesson_position[7:0];status_bytes[1847:1840]=lesson_hand;status_bytes[1855:1848]=lesson_note;status_bytes[1871:1856]=lesson_correct;status_bytes[1887:1872]=lesson_wrong;status_bytes[1895:1888]=online;status_bytes[1903:1896]={4'b0,octave_right,octave_left};status_bytes[1791:1664]=expression_config;status_bytes[15:8]=running;status_bytes[23:16]=config_wait;status_bytes[31:24]=stop_reason;
  status_bytes[39:32]=profiles[1:0];status_bytes[47:40]=profiles[3:2];status_bytes[55:48]=presets[2:0];status_bytes[63:56]=presets[5:3];
  status_bytes[71:64]=chord;status_bytes[79:72]=effect_mode;status_bytes[87:80]=wet;status_bytes[95:88]=test_gain[7:0];
  status_bytes[103:96]=use_host ? {selected_valid[0],3'b0,selected_zone[3:0]} : {sensor_status[4],3'b0,sensor_status[21:18]};status_bytes[111:104]=use_host ? {selected_valid[1],3'b0,selected_zone[7:4]} : {sensor_status[260],3'b0,sensor_status[277:274]};
  status_bytes[119:112]=use_host ? hit_zone[3:0] : sensor_status[25:22];status_bytes[127:120]=use_host ? hit_zone[7:4] : sensor_status[281:278];
  status_bytes[159:128]=key_count[0];status_bytes[191:160]=key_count[1];status_bytes[223:192]=last_event;
  status_bytes[231:224]=last_hand;status_bytes[239:232]=last_velocity;status_bytes[247:240]=active_effect;status_bytes[255:248]=actual_wet;
  status_bytes[672+:8]=29;status_bytes[680+:8]=lite_pending;status_bytes[688+:8]=lite_judging;status_bytes[696+:8]=lite_glide;status_bytes[704+:8]=lite_vibrato;status_bytes[712+:16]=lite_glide_ms;status_bytes[728+:8]=test_pressed|test_pressed2;status_bytes[287:256]=0;status_bytes[319:288]=0;status_bytes[351:320]=stolen;status_bytes[383:352]=underflows;
  status_bytes[415:384]=stereo_clips+fx_clips;status_bytes[447:416]=fx_drops;status_bytes[479:448]=rx_errors;status_bytes[511:480]=drops[31:0]+drops[63:32];
  status_bytes[543:512]=cap_event;status_bytes[575:544]=skipped_captures;status_bytes[607:576]=0;status_bytes[615:608]=cap_busy;
  status_bytes[623:616]=gain[7:0];status_bytes[631:624]={4'b0,2'b11,key1_n,key0_n};status_bytes[655:640]=config_revision;
  status_bytes[639:632]={6'b0,gain[8],test_gain[8]};
  status_bytes[1455:1440]=hold_ms_left;status_bytes[1471:1456]=hold_ms_right;status_bytes[1479:1472]={4'b0,release_ids};status_bytes[1487:1480]=pa_en;
  status_bytes[1495:1488]={6'b0,piano_hold};status_bytes[1511:1496]=piano_coefficients[15:0];status_bytes[1527:1512]=piano_coefficients[31:16];
  status_bytes[1543:1536]=sine_mode;status_bytes[1551:1544]=sine_enable;status_bytes[1583:1552]=sine_frequency;status_bytes[1599:1584]=sine_amplitude;
  status_bytes[1607:1600]=sine_channels;status_bytes[1615:1608]=monitor_count;status_bytes[1647:1616]=monitor_ids;status_bytes[1655:1648]=sine_active;
  status_bytes[1927:1920]=ui_hand;status_bytes[1935:1928]=ui_level;status_bytes[1943:1936]=ui_group;
  status_bytes[1951:1944]=ui_item;status_bytes[1959:1952]=lesson_mouse;status_bytes[1967:1960]=lesson_phase;
  status_bytes[1975:1968]=feedback_hand;status_bytes[1983:1976]=feedback_zone;status_bytes[1999:1984]=lesson_serial;
  status_bytes[2007:2000]=ui_notice;status_bytes[2015:2008]=calibration_result;status_bytes[2023:2016]=lesson_finished;
  status_bytes[2031:2024]=!running;status_bytes[2047:2032]=ui_serial;
  status_bytes[2055:2048]={6'b0,wrist_enable};status_bytes[2063:2056]={6'b0,wrist_invert};
  status_bytes[2071:2064]={6'b0,wrist_pressed};status_bytes[2079:2072]={6'b0,wrist_fresh};
  status_bytes[2087:2080]={4'b0,wrist_octave};status_bytes[2095:2088]={4'b0,wrist_snapshot};
  status_bytes[2127:2096]=wrist_bend;status_bytes[2159:2128]=wrist_serial;
  status_bytes[2191:2160]=use_host ? test_pitch : sensor_pitch;
  status_bytes[2223:2192]=ticks;
  info_bytes=0;info_bytes[15:0]=response_seq;info_bytes[47:16]=50000000;info_bytes[79:48]=48000;info_bytes[87:80]=32;info_bytes[103:88]=2048;
  info_bytes[111:104]=8'h44;
  info_bytes[119:112]=8'h55;
  info_bytes[127:120]=8'h4f;
  info_bytes[135:128]=8'h30;
  info_bytes[143:136]=8'h34;
  info_bytes[151:144]=8'h2d;
  info_bytes[159:152]=8'h4c;
  info_bytes[167:160]=8'h49;
  info_bytes[175:168]=8'h56;
  info_bytes[183:176]=8'h45;
  info_bytes[191:184]=8'h20;
  info_bytes[199:192]=8'h33;
  info_bytes[207:200]=8'h2e;
  info_bytes[215:208]=8'h33;
  info_bytes[223:216]=8'h2b;
  info_bytes[231:224]=8'h47;
  info_bytes[239:232]=8'h45;
  info_bytes[247:240]=8'h53;
  info_bytes[255:248]=8'h54;
  info_bytes[263:256]=8'h32;
  info_bytes[271:264]=8'h37;
  info_bytes[279:272]=8'h2b;
  info_bytes[287:280]=8'h4d;
  info_bytes[295:288]=8'h50;
  info_bytes[303:296]=8'h55;
  info_bytes[311:304]=8'h36;
  info_bytes[319:312]=8'h30;
  info_bytes[327:320]=8'h35;
  info_bytes[335:328]=8'h30;
  info_bytes[343:336]=8'h2b;
  info_bytes[351:344]=8'h4c;
  info_bytes[359:352]=8'h49;
  info_bytes[367:360]=8'h54;
  info_bytes[375:368]=8'h45;
  info_bytes[383:376]=8'h32;
  info_bytes[391:384]=8'h39;
  info_bytes[399:392]=8'h2b;
  info_bytes[407:400]=8'h4b;
  info_bytes[415:408]=8'h45;
  info_bytes[423:416]=8'h59;
  info_bytes[431:424]=8'h33;
  info_bytes[439:432]=8'h30;
  info_bytes[447:440]=8'h2b;
  info_bytes[455:448]=8'h4c;
  info_bytes[463:456]=8'h33;
  info_bytes[471:464]=8'h33;
  info_bytes[479:472]=8'h31;

 end
 reg tx_start;reg[7:0]tx_kind,tx_payload,saved_code;reg[15:0]tx_len,saved_seq;
 reg[31:0]saved_tick;reg[511:0]saved_info;reg[383:0]saved_meta;reg[255:0]cap_gesture;
 wire[15:0]tx_addr;wire[7:0]tx_byte;wire tx_valid,tx_uart_ready,tx_busy,tx_done;
 wire event_sending=!tx_busy && !tx_start && !tx_done && !response_pending && event_pending!=0;
 wire[1:0]event_taking=event_sending ? (event_pending[0] ? 2'b01 : 2'b10) : 2'b00;
 wire[1:0]event_replacing=event_changed & event_pending & ~event_taking & {2{!use_host}};
 wire[1:0]event_lost={1'b0,event_replacing[0]}+{1'b0,event_replacing[1]};
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
   141:tx_payload=saved_score[tx_addr[5:0]*8+:8];
   140:tx_payload=saved_event[tx_addr[4:0]*8+:8];
   136:tx_payload=saved_status[tx_addr[8:0]*8+:8];
   137:tx_payload=saved_meta[tx_addr[5:0]*8+:8];
   139:case(tx_addr)
    0:tx_payload=cap_id[7:0];1:tx_payload=cap_id[15:8];2:tx_payload=cap_monitor_count;
    3,4,5,6:tx_payload=cap_monitor_ids[(tx_addr-3)*8+:8];7:tx_payload=cap_sine_mode;
    8,9,10,11:tx_payload=cap_sine_frequency[(tx_addr-8)*8+:8];12:tx_payload=cap_sine_amplitude[7:0];13:tx_payload=cap_sine_amplitude[15:8];14:tx_payload=cap_sine_channels;
   endcase
   130,138:case(tx_addr)
    0:tx_payload=cap_id[7:0];1:tx_payload=cap_id[15:8];2:tx_payload=upload_offset[7:0];3:tx_payload=upload_offset[15:8];
    4:tx_payload=cap_points[7:0];5:tx_payload=cap_points[15:8];6:tx_payload=8'h80;7:tx_payload=8'hbb;8,9:tx_payload=0;
    default:tx_payload=cap_word[bus_byte*8+:8];
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
 always @(posedge core_clk)begin
  if(!rst_n)begin use_host<=0;epoch_source<=0;selected_epochs<=0;end
  else begin use_host<=requested_host;epoch_source<=use_host;selected_epochs<=use_host ? host_epochs : sensor_epochs;end
 end
 genvar wh;generate for(wh=0;wh<2;wh=wh+1)begin:wrists
  wire playable_w=use_host ? running : sensor_status[wh*256] && sensor_status[wh*256+1] && !sensor_status[wh*256+2] && sensor_status[wh*256+7] && sensor_status[wh*256+8+:2]>=2 && !sensor_status[wh*256+6];
  reg signed[15:0]pitch_local;reg pose_local,playable_local,zone_ok_local;reg[3:0]zone_local;
  always @(posedge core_clk)begin
   if(!rst_n || !source_ready || !running || key_stop || config_wait || calibrate[wh] || sensor_cancel_now[wh] || cancel[wh])begin pitch_local<=0;pose_local<=0;playable_local<=0;zone_local<=0;zone_ok_local<=0;end
   else begin pitch_local<=use_host ? test_pitch[wh*16+:16] : sensor_pitch[wh*16+:16];pose_local<=use_host ? test_pose_valid[wh] : sensor_pose_valid[wh];playable_local<=playable_w;
    zone_local<=use_host ? selected_zone[wh*4+:4] : sensor_status[wh*256+18+:4];zone_ok_local<=use_host ? selected_valid[wh] : sensor_status[wh*256+4];end
  end
  lite_hand_gesture gesture(.clk(core_clk),.rst_n(rst_n),
   .clear(!running || !source_ready || key_stop || config_wait || calibrate[wh] || sensor_cancel_now[wh] || cancel[wh]),
   .enabled(gesture_enable[wh]),.invert(wrist_invert[wh]),
   .button_n(use_host ? !test_pressed[wh] : wrist_button_n[wh]),.button2_n(use_host ? !test_pressed2[wh] : wrist_button2_n[wh]),
   .input_profile(profiles[wh*2+:2]),.teaching(operating_mode==2),.lesson_octave(lesson_octave),.button_event(button_event[wh]),.button_payload(button_payload[wh*32+:32]),.combo_active(combo_active[wh]),.glide_on(lite_glide[wh]),.vibrato_on(lite_vibrato[wh]),.glide_ms(lite_glide_ms),.pending(lite_pending[wh]),.judging(lite_judging[wh]),
   .pose_valid(pose_local),.playable(playable_local),
   .pitch(pitch_local),
   .zone(zone_local),
   .zone_valid(zone_ok_local),
   .hit(event_valid && event_ready && !legato_taken && events[31:30]==0 && events[29]==wh),
   .hit_zone(events[28:25]),.hit_profile(events[24:23]),.hit_octave(events[22:21]),.chord(chord && wh==0),
   .pressed(wrist_pressed[wh]),.octave(wrist_octave[wh*2+:2]),.octave_fresh(wrist_fresh[wh]),
   .hit_octave_snapshot(wrist_snapshot[wh*2+:2]),.bend(wrist_bend[wh*16+:16]),.serial(wrist_serial[wh*16+:16]),.debug_state(wrist_debug[wh*56+:56]));
 end endgenerate
 performance_controls #(.LONG_MS(800)) encoder(.clk(core_clk),.rst_n(rst_n),.enabled(1'b1),.encoder_a(encoder_a),.encoder_b(encoder_b),.encoder_button_n(encoder_button_n),.pedal_n(1'b1),.wrist_button_n(2'b11),.encoder_step(local_step),.encoder_direction(local_direction),.encoder_short(local_short),.encoder_long(local_long),.pedal_toggle(unused_pedal),.wrist_short(wrist_short),.wrist_long(wrist_long),.button_ready(buttons_ready),.invalid_transitions(encoder_errors));
 duo04_menu menu(.clk(core_clk),.rst_n(rst_n),.step(local_step),.direction(local_direction),.short_press(local_short),.long_press(local_long),
 .keys(key_actions),.remote_valid(remote_ui),.remote_action(remote_action_q),.running(running),.mode(operating_mode),.teaching_active(operating_mode==2),.finished(lesson_finished),
 .profiles(profiles),.presets(presets),.volume(test_gain),.current_value(menu_current),.page(menu_page),.field(menu_field),.editing(menu_editing),
 .write(menu_write),.value(menu_value),.active_hand(ui_hand),.level(ui_level),.group_id(ui_group),.item(ui_item),.stop(ui_stop),.notice(ui_notice),.serial(ui_serial));
 two_hand_i2c_core sensors(.button_valid(button_event & {2{!use_host && running}}),.button_data(button_payload),.clk(core_clk),.rst_n(rst_n),.enabled({2{!use_host && !config_wait}}),.wrist_enable(2'b00),.wrist_fresh(wrist_fresh),.wrist_octaves(wrist_octave),.hit_snapshot_ticks(sensor_hit_snapshots),.hit_actual_octaves(sensor_hit_octaves),.hit_used_snapshots(sensor_hit_used),.pose_samples(sensor_pose_valid),.pose_pitches(sensor_pitch),.force_reset(sensor_force_reset),.calibrate(calibrate),.express(2'b11),.mirror(yaw_invert),.layout_profile(profiles),.scl_in(imu_scl),.sda_in(imu_sda),.int_n(2'b11),.scl_low(scl_low),.sda_low(sda_low),.reset_low(reset_low),.online(online),.status(sensor_status),.diagnostic(sensor_diagnostic),.report_rates(sensor_rates),.processing_overruns(sensor_overruns),.event_valid(sensor_valid),.event_ready(sensor_ready),.event_data(sensor_events),.release_pending(sensor_release),.release_ack(sensor_ack),.epochs(sensor_epochs),.event_drops(sensor_drops),.cancelled_events(sensor_cancelled),.cancel_now(sensor_cancel_now));
 // Keep accepted event payload/hand/zone together across both observation
 // stages. Stop/restart/mode changes discard delayed teaching feedback.
 lesson_event_pipeline lesson_events(.clk(core_clk),.rst_n(rst_n),
 .flush(!running || !source_ready || operating_mode!=2 || lesson_restart || key_stop || cancel!=0),
 .accepted(event_valid && event_ready),.event_data(events),.epochs(epochs),
 .hit(lesson_hit),.hand(played_hand),.note(played_note),.zone(played_zone));
 duo27_lesson lesson(.clk(core_clk),.rst_n(rst_n),.enabled(running && operating_mode==2),.restart(lesson_restart),.clear_feedback(lesson_clear),.song(lesson_song),
 .hit(lesson_hit),.hand(played_hand),.note(played_note),.zone(played_zone),
 .score_loaded(score_loaded),.score_total(score_total),.score_word(score_word),.score_address(score_address),.target_octave(lesson_octave),.hold_ms(lesson_hold_ms),.hold_samples(lesson_hold_samples),.target_ready(lesson_target_ready),
 .position(lesson_position),.correct(lesson_correct),.wrong(lesson_wrong),.target_hand(lesson_hand),.target_note(lesson_note),.target_zone(lesson_zone),
 .finished(lesson_finished),.last_correct(lesson_feedback),.feedback(lesson_phase),.feedback_hand(feedback_hand),.feedback_zone(feedback_zone),.event_serial(lesson_serial));
 always @(posedge core_clk)begin
  if(!rst_n)begin
   score_seq<=0;saved_score<=0;score_status_pending<=0;score_timer<=0;
   lite_glide<=0;lite_vibrato<=0;lite_glide_ms<=80;test_pressed2<=0;yaw_invert<=0;wrist_enable<=3;wrist_invert<=0;test_pressed<=0;test_pitch<=0;test_pose_valid<=0;test_pose_div<=0;test_pose_age[0]<=2000000;test_pose_age[1]<=2000000;
   lesson_clear<=0;lesson_mouse<=0;lesson_saved<=0;saved_profiles<=0;saved_octaves<=0;saved_chord<=0;sensor_force_reset<=0;calibration_result<=0;calibration_mask<=0;calibration_age<=0;calibration_seen<=0;
   seen_ui_serial<=0;seen_lesson_serial<=0;seen_phase<=0;seen_position<=0;ticks<=0;link_age<=0;local_write<=0;local_field<=0;local_value<=0;operating_mode<=0;octave_left<=0;octave_right<=0;lesson_song<=0;lesson_restart<=0;calibrate<=0;running<=0;stop_reason<=0;profiles<=0;presets<=0;chord<=0;effect_mode<=0;wet<=128;test_gain<=8;
   hold_ms_left<=1500;hold_ms_right<=1500;hold_samples_left<=72000;hold_samples_right<=72000;release_ids<=5;
   expression_config<=0;sine_enable<=0;sine_mode<=0;sine_frequency<=89478485;sine_amplitude<=1036;sine_channels<=3;
   monitor_count<=0;monitor_ids<=32'hffff1000;cap_monitor_count<=0;cap_monitor_ids<=32'hffff1000;
   held_voices<=0;upload_voice<=0;voice_meta_pending<=0;cap_sine_mode<=0;cap_sine_frequency<=0;cap_sine_amplitude<=0;cap_sine_channels<=0;
   piano_hold<=0;piano_coefficients<={16'd134,16'd134};
   selected_valid<=0;selected_zone<=0;hit_zone<=0;hit_profile<=0;hits0<=0;hits1<=0;last_event<=0;last_hand<=0;last_velocity<=0;skipped_captures<=0;config_revision<=0;
   push<=0;cancel<=0;push_data<=0;clear_history<=0;response_pending<=0;response_kind<=129;response_code<=0;response_seq<=0;
   config_wait<=0;pending_config<=0;config_delay<=0;strike_wait<=0;pending_strike<=0;strike_seq<=0;
   output_mute<=0;cap_active<=0;cap_ready<=0;cap_armed<=0;cap_wait_render<=0;cap_start_on_pcm<=0;cap_wr<=0;cap_points<=512;cap_id<=0;upload_offset<=0;cap_event<=0;cap_tick<=0;cap_hand<=0;meta_pending<=0;cap_revision<=0;
   event_drop_count<=0;event_pending<=0;event_seen<=0;event_changed<=0;saved_event<=0;event_mail[0]<=0;event_mail[1]<=0;
   held_dry_left<=0;held_dry_right<=0;status_timer<=0;status_pending<=0;last_sensor_hits<=0;
   tx_start<=0;tx_kind<=0;tx_len<=0;saved_seq<=0;saved_code<=0;saved_tick<=0;saved_info<=0;saved_status<=0;saved_meta<=0;cap_gesture<=0;capture_gap<=0;
  end else begin
   if(sine_mode && !sine_enable && !sine_active)sine_mode<=0;
   sensor_force_reset<=0;test_pose_valid<=0;
   if(test_pose_div==249999)begin test_pose_div<=0;test_pose_valid<={test_pose_age[1]<750000,test_pose_age[0]<750000};end else test_pose_div<=test_pose_div+1'b1;
   for(ta=0;ta<2;ta=ta+1)if(test_pose_age[ta]<2000000)test_pose_age[ta]<=test_pose_age[ta]+1'b1;
   if(!use_host || !running || key_stop)test_pressed<=0;
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
    seen_ui_serial<=ui_serial;seen_lesson_serial<=lesson_serial;seen_phase<=lesson_phase;seen_position<=lesson_position;status_pending<=1;score_status_pending<=1;
   end
   if(last_sensor_hits!={key_count[1],key_count[0]})begin last_sensor_hits<={key_count[1],key_count[0]};status_pending<=1;end
   if(status_timer==1249999)begin status_timer<=0;status_pending<=1;end else status_timer<=status_timer+1'b1;
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
      if(!cap_busy)begin cap_monitor_count<=0;cap_monitor_ids<=monitor_ids;cap_sine_mode<=sine_mode;cap_sine_frequency<=sine_frequency;cap_sine_amplitude<=sine_amplitude;cap_sine_channels<=sine_channels;cap_armed<=1;cap_event<=pending_strike[31:0];cap_hand<=pending_strike[32];cap_points<=512;cap_revision<=config_revision;end
      else skipped_captures<=skipped_captures+1'b1;
     end
    end else response_code<=3;
    status_pending<=1;
   end
   if(cap_armed && committed && committed_id==cap_event[7:0] && committed_hand==cap_hand)begin cap_armed<=0;cap_wait_render<=1;end
   if(input_accepted && !sine_mode)begin
    held_voices<=0;
    held_dry_left<=dry_left;held_dry_right<=dry_right;
    if(cap_wait_render)begin cap_wait_render<=0;cap_start_on_pcm<=1;end
   end
   if(pcm_valid && (cap_active || begin_capture))begin
    capture_mem[begin_capture ? 11'd0 : cap_wr]<=capture_word;
    if(begin_capture)begin
     cap_wait_render<=0;
     cap_start_on_pcm<=0;cap_active<=1;cap_wr<=1;cap_gesture<=status_bytes[2303:2048];cap_tick<=ticks;cap_id<=cap_id+1'b1;
    end else begin
     if({5'b0,cap_wr}==cap_points-1'b1)begin cap_active<=0;cap_ready<=1;upload_offset<=0;meta_pending<=1;end
     else cap_wr<=cap_wr+1'b1;
    end
   end
   if(score_timer==4999999)begin score_timer<=0;score_status_pending<=1;end else score_timer<=score_timer+1'b1;
   if(score_ack)begin response_pending<=1;response_kind<=129;response_code<=score_code;response_seq<=score_seq;score_status_pending<=1;end
   if(score_committed)begin running<=0;cancel<=3;clear_history<=3;lesson_restart<=1;score_status_pending<=1;end
   if(use_host && running)begin
    for(ta=0;ta<2;ta=ta+1)if(button_event[ta])begin push[ta]<=1;push_data[ta*32+:32]<={button_payload[ta*32+30+:2],ta==1,button_payload[ta*32+:29]};end
   end
   if(cmd_done)begin
    link_age<=0;response_seq<=cmd_seq;response_kind<=129;response_code<=0;response_pending<=1;
    case(cmd)
     69,70,71,72,73,74:begin
      score_seq<=cmd_seq;response_pending<=0;
      if(cmd==69)begin running<=0;cancel<=3;clear_history<=3;cap_armed<=0;cap_wait_render<=0;sine_enable<=0;end
     end
     1:begin response_kind<=128;if(use_host)begin sine_enable<=0;voice_meta_pending<=0;upload_voice<=0;running<=0;cancel<=3;clear_history<=3;selected_valid<=0;stop_reason<=0;cap_armed<=0;cap_wait_render<=0;cap_active<=0;cap_ready<=0;meta_pending<=0;cap_start_on_pcm<=0;config_wait<=0;end end
     75:if(cmd_len!=4 || cmd_data[7:0]>3 || cmd_data[15:8]>3 || cmd_data[31:16]<20 || cmd_data[31:16]>500)response_code<=2;
        else begin lite_glide<=cmd_data[1:0];lite_vibrato<=cmd_data[9:8];lite_glide_ms<=cmd_data[24:16];status_pending<=1;end
     76:if(cmd_len!=5 || !use_host || cmd_data[7:0]>1 || cmd_data[15:8]>3 || $signed(cmd_data[31:16])>1440 || $signed(cmd_data[31:16])< -1440)response_code<=2;
        else begin test_pressed[cmd_data[0]]<=cmd_data[8];test_pressed2[cmd_data[0]]<=cmd_data[9];test_pitch[cmd_data[0]*16+:16]<=cmd_data[31:16];test_pose_valid[cmd_data[0]]<=1;test_pose_age[cmd_data[0]]<=0;status_pending<=1;end
     64:if(cmd_len!=2 || cmd_data[7:0]>3 || cmd_data[15:8]>3 || running)response_code<=2;
        else begin wrist_enable<=cmd_data[1:0];wrist_invert<=cmd_data[9:8];config_revision<=config_revision+1'b1;status_pending<=1;end
     65:if(cmd_len!=4 || cmd_data[7:0]>1 || cmd_data[15:8]>1 || $signed(cmd_data[31:16])>1440 || $signed(cmd_data[31:16])< -1440 || !use_host || operating_mode==2)response_code<=2;
        else begin test_pressed[cmd_data[0]]<=cmd_data[8];test_pitch[cmd_data[0]*16+:16]<=cmd_data[31:16];test_pose_valid[cmd_data[0]]<=1;test_pose_age[cmd_data[0]]<=0;status_pending<=1;end
     20:response_kind<=134;
     21:if(cmd_len!=1 || cmd_data[7:0]!=0)response_code<=2;
     17:if((cmd_len!=1 && cmd_len!=3) || cmd_data[7:0]!=0 || (cmd_len==3 && cmd_data[23:8]!=512 && cmd_data[23:8]!=2048))response_code<=2;
        else if(cap_busy || score_uploading)response_code<=1;
        else begin cap_monitor_count<=0;cap_monitor_ids<=monitor_ids;cap_sine_mode<=sine_mode;cap_sine_frequency<=sine_frequency;cap_sine_amplitude<=sine_amplitude;cap_sine_channels<=sine_channels;cap_wait_render<=1;cap_event<=0;cap_points<=cmd_len==3 ? cmd_data[23:8] : 2048;cap_revision<=config_revision;end
     48:if(operating_mode!=1 || !valid_config)response_code<=2;
        else if(config_wait || sine_active)response_code<=1;
        else begin
         config_wait<=1;config_delay<=0;pending_config<=cmd_len==20 ? cmd_data[159:0] : {16'd134,16'd134,8'd0,(cmd_len==15 ? cmd_data[119:0] : {8'h05,16'd1500,16'd1500,8'd0,cmd_data[71:0]})};cancel<=3;clear_history<=3;running<=0;selected_valid<=0;
         response_pending<=0;cap_armed<=0;cap_wait_render<=0;
        end
     49:if(cmd_len!=3 || cmd_data[7:0]>1 || cmd_data[15:8]>1 || (cmd_data[8] && !valid_zone({6'b0,profiles[cmd_data[0]*2+:2]},cmd_data[23:16])))response_code<=2;
        else begin selected_valid[cmd_data[0]]<=cmd_data[8];selected_zone[cmd_data[0]*4+:4]<=cmd_data[19:16];status_pending<=1;end
     50:if(1'b1)response_code<=4;
        else if(!valid_strike)response_code<=2;
        else if(!use_host || !running || (1'b0) || config_wait || release_pending[strike_hand] || cmd_data[49:48]!=profiles[strike_hand*2+:2] || (operating_mode==2 && cmd_data[63:56]!=0))response_code<=3;
        else begin
         push[strike_hand]<=1;push_data[strike_hand*32+:32]<={2'b0,strike_hand,cmd_data[43:40],cmd_data[49:48],(operating_mode==2 ? lesson_octave : gesture_enable[strike_hand] ? wrist_snapshot[strike_hand*2+:2] : cmd_data[57:56]),cmd_data[70:64],2'b0,cmd_data[7:0],4'b0};
         pending_strike<=cmd_data[79:0];strike_seq<=cmd_seq;strike_wait<=1;response_pending<=0;
        end
     51:begin lesson_clear<=1;sine_enable<=0;running<=0;cancel<=3;clear_history<=3;selected_valid<=0;stop_reason<=1;config_wait<=0;cap_armed<=0;cap_wait_render<=0;status_pending<=1;end
     52:status_pending<=1;
     53:begin end
     54,55:response_code<=4; // removed monitor selection and calibration source
     57:response_code<=4; // removed oscillator/legacy expression command
     56:response_code<=4;
     61:if(cmd_len!=1 || cmd_data[7:0]>=12)response_code<=2;else if(cmd_data[7:0]!=11 && (local_step || local_short || local_long || key_actions!=0))response_code<=1;else status_pending<=1;
     62:if(cmd_len!=2 || cmd_data[7:0]>1 || cmd_data[15:8]>3 || (cmd_data[15:8]==3 && !score_loaded) || menu_write || local_write)response_code<=2;
        else begin
         if(operating_mode!=2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;end
         operating_mode<=2;profiles<=cmd_data[15:8]==3 ? {score_profile,score_profile} : 4'b0;octave_left<=0;octave_right<=0;chord<=0;sine_enable<=0;sine_mode<=0;
         lesson_mouse<=cmd_data[0];lesson_song<=cmd_data[9:8];running<=0;cancel<=3;clear_history<=3;lesson_restart<=1;status_pending<=1;config_revision<=config_revision+1'b1;end
     63:if(cmd_len!=1 || cmd_data[7:0]>4 || local_write || menu_write)response_code<=2;
        else begin local_write<=1;local_field<=27;local_value<={8'b0,cmd_data[7:0]};end
     60:if(cmd_len!=3 || !valid_edit(cmd_data[7:0],cmd_data[23:8]))response_code<=2;
        else if(local_write || menu_write || (operating_mode==2 && (cmd_data[7:0]==3 || cmd_data[7:0]==4 || cmd_data[7:0]==5 || cmd_data[7:0]==6 || cmd_data[7:0]==7)))response_code<=1;
        else begin local_write<=1;local_field<=cmd_data[7:0];local_value<=cmd_data[23:8];end
     68:if(running)response_code<=3;else if(cmd_len!=2 || cmd_data[7:0]>1 || cmd_data[15:8]>1)response_code<=2;else begin yaw_invert[cmd_data[0]]<=cmd_data[8];cancel[cmd_data[0]]<=1;clear_history[cmd_data[0]]<=1;status_pending<=1;config_revision<=config_revision+1'b1;end
     67:if(cmd_len!=1 || cmd_data[7:0]>1)response_code<=2;else begin output_mute<=cmd_data[0];status_pending<=1;end
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
      if(operating_mode!=2 && edit_value==2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;profiles<=teaching_profiles;octave_left<=0;octave_right<=0;chord<=0;end
      else if(operating_mode==2 && edit_value!=2 && lesson_saved)begin profiles<=saved_profiles;octave_left<=saved_octaves[1:0];octave_right<=saved_octaves[3:2];chord<=saved_chord;lesson_saved<=0;end
      operating_mode<=edit_value[1:0];running<=0;cancel<=3;clear_history<=3;sine_enable<=0;sine_mode<=0;lesson_restart<=1;cap_armed<=0;cap_wait_render<=0;end
     1:if(edit_value<4)presets[2:0]<=edit_value[2:0];
     2:if(edit_value<4)presets[5:3]<=edit_value[2:0];
     3:if(edit_value<3)profiles[1:0]<=edit_value[1:0];
     4:if(edit_value<3)profiles[3:2]<=edit_value[1:0];
     5:if(edit_value<4)octave_left<=edit_value[1:0];
     6:if(edit_value<4)octave_right<=edit_value[1:0];
       29,30:begin if(!running)wrist_enable[edit_field-29]<=edit_value[0];end
       31,32:begin if(!running)wrist_invert[edit_field-31]<=edit_value[0];end
       7:if(chord!=edit_value[0])begin chord<=edit_value[0];running<=0;cancel<=3;clear_history<=3;end 8:if(edit_value<=256)test_gain<=edit_value[8:0];
     9:if(edit_value<4)effect_mode<=edit_value[1:0];10:if(edit_value<256)wet<=edit_value[7:0];
     11:if(edit_value>=100 && edit_value<=10000)begin hold_ms_left<=edit_value;hold_samples_left<=edit_value*32'd48;end
     12:if(edit_value>=100 && edit_value<=10000)begin hold_ms_right<=edit_value;hold_samples_right<=edit_value*32'd48;end
     13:if(edit_value<3)release_ids[1:0]<=edit_value[1:0];14:if(edit_value<3)release_ids[3:2]<=edit_value[1:0];
     15:begin lite_vibrato[0]<=edit_value[0];end
     16:begin lite_vibrato[1]<=edit_value[0];end
     17:lite_glide[0]<=edit_value[0];
     18:lite_glide[1]<=edit_value[0];
     19:if(edit_value<4)begin if(operating_mode==2)profiles<=edit_value==3 ? {score_profile,score_profile} : 4'b0;lesson_song<=edit_value[1:0];lesson_restart<=1;running<=0;cancel<=3;clear_history<=3;end
     20:begin if(operating_mode!=2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;end operating_mode<=2;octave_left<=0;octave_right<=0;running<=score_lesson_ok && !score_uploading;lesson_restart<=1;cancel<=3;clear_history<=3;profiles<=teaching_profiles;chord<=0;sine_mode<=0;sine_enable<=0;end
     21:begin calibrate<=3;calibration_mask<=3;calibration_age<=0;calibration_seen<=0;calibration_result<=1;end
     23:begin lesson_mouse<=edit_value[0];running<=0;cancel<=3;clear_history<=3;lesson_restart<=1;end
     25:begin calibrate<=edit_value[0] ? 2 : 1;calibration_mask<=edit_value[0] ? 2 : 1;calibration_age<=0;calibration_seen<=0;calibration_result<=1;end
     28:begin sensor_force_reset<=edit_value[0] ? 2 : 1;cancel<=edit_value[0] ? 2 : 1;end
     27:begin
      if(edit_value==0 || edit_value==2)begin stop_reason<=edit_value==0 ? 1 : 6;if(edit_value==0)lesson_clear<=1;running<=0;cancel<=3;clear_history<=3;end
      else if(edit_value==3)begin if(operating_mode==2 && !lesson_finished && score_lesson_ok && !score_uploading)begin running<=1;stop_reason<=0;end end
      else begin
       if(operating_mode!=2)begin saved_profiles<=profiles;saved_octaves<={octave_right,octave_left};saved_chord<=chord;lesson_saved<=1;end
       operating_mode<=2;profiles<=teaching_profiles;octave_left<=0;octave_right<=0;chord<=0;running<=score_lesson_ok && !score_uploading;stop_reason<=0;lesson_restart<=1;cancel<=3;clear_history<=3;sine_enable<=0;sine_mode<=0;
      end
     end
     22:begin stop_reason<=edit_value[0] ? 0 : (operating_mode==2 ? 6 : 1);running<=edit_value[0] && !score_uploading && (operating_mode!=2 || score_lesson_ok);if(!edit_value[0])begin cancel<=3;clear_history<=3;end end
    endcase
   end
   if(operating_mode==2 && !lesson_mouse && running && !online[lesson_hand])begin running<=0;cancel<=3;clear_history<=3;stop_reason<=5;status_pending<=1;end
   if(score_uploading)running<=0;
   if(key_stop)begin lesson_clear<=1;running<=0;sine_enable<=0;cancel<=3;clear_history<=3;config_wait<=0;local_write<=0;selected_valid<=0;cap_armed<=0;cap_wait_render<=0;stop_reason<=3;status_pending<=1;end
   if(!tx_busy && !tx_start && !tx_done)begin
    saved_tick<=ticks;
    if(response_pending)begin
     saved_seq<=response_seq;saved_code<=response_code;saved_info<=info_bytes;tx_kind<=response_kind;tx_len<=response_kind==128 ? 60 : 3;
     tx_start<=1;response_pending<=0;
    end else if(event_pending!=0)begin
     saved_event<=event_pending[0] ? event_mail[0] : event_mail[1];event_pending[event_pending[0] ? 0 : 1]<=0;tx_kind<=140;tx_len<=32;tx_start<=1;
    end else if(score_status_pending)begin
     saved_score<=0;saved_score[7:0]<=1;saved_score[15:8]<=score_loaded;saved_score[23:16]<=score_uploading;saved_score[31:24]<=score_busy;
     saved_score[63:32]<=score_crc;saved_score[79:64]<={4'b0,score_total};saved_score[95:80]<={4'b0,lesson_position};
     saved_score[103:96]<=score_profile;saved_score[111:104]<=lesson_hand;saved_score[119:112]<=lesson_note;saved_score[127:120]<=lesson_zone;
     saved_score[135:128]<=lesson_octave;saved_score[143:136]<=lesson_phase;saved_score[151:144]<=lesson_finished;saved_score[159:152]<=lesson_target_ready;
     saved_score[191:160]<=score_transfer;saved_score[207:192]<={4'b0,score_uploaded};saved_score[215:208]<=score_code;saved_score[223:216]<=operating_mode==2 && lesson_song==3;
     saved_score[239:224]<=score_revision;saved_score[255:240]<={5'b0,score_read_index};saved_score[287:256]<=score_readback;saved_score[303:288]<=score_read_revision;
     saved_score[319:304]<=lesson_hold_ms;saved_score[335:320]<=lesson_correct;saved_score[351:336]<=lesson_wrong;
     tx_kind<=141;tx_len<=48;tx_start<=1;score_status_pending<=0;
    end else if(meta_pending)begin
     saved_meta<={cap_gesture,16'b0,8'd5,8'd2,cap_revision,cap_tick,cap_event,cap_id};tx_kind<=137;tx_len<=48;tx_start<=1;meta_pending<=0;voice_meta_pending<=0;upload_voice<=0;
    end else if(voice_meta_pending)begin tx_kind<=139;tx_len<=16;tx_start<=1;voice_meta_pending<=0;
    end else if(status_pending)begin saved_status<=status_bytes;tx_kind<=136;tx_len<=496;tx_start<=1;status_pending<=0;end
    else if(cap_ready && capture_gap==0)begin tx_kind<=130;tx_len<=330;tx_start<=1;end
   end
   if(tx_done && (tx_kind==130 || tx_kind==138))begin
    capture_gap<=CAPTURE_GAP_CYCLES;
    if(1'b0)upload_voice<=1;
    else begin upload_voice<=0;if(upload_offset==cap_points-32)cap_ready<=0;else upload_offset<=upload_offset+32;end
   end
   event_seen<={key_count[1],key_count[0]};
   event_changed<={(key_count[1]!=event_seen[63:32] && key_count[1]!=0),(key_count[0]!=event_seen[31:0] && key_count[0]!=0)};
   if(event_lost!=0)event_drop_count<=event_drop_count+{30'b0,event_lost};
   for(eh=0;eh<2;eh=eh+1)if(event_changed[eh])begin
    event_pending[eh]<=1;
    event_mail[eh]<={32'b0,event_drop_count,32'b0,32'b0,ticks,key_count[eh],8'b0,8'b0,{1'b0,button_payload[eh*32+14+:7]},
     {6'b0,button_payload[eh*32+23+:2]},{6'b0,button_payload[eh*32+21+:2]},{4'b0,button_payload[eh*32+25+:4]},eh[7:0],8'd1};
   end

  end
 end
endmodule


