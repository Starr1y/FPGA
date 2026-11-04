// Two independent physical I2C buses may both use BNO085 address 0x4A.
// This is a reusable core, not a board download top: pad/pin and button adapters are external.
module two_hand_i2c_core #(
 parameter CLK_HZ=50000000,HALF_DIV=100,
 parameter RESET_TICKS=CLK_HZ/100,BOOT_TICKS=CLK_HZ*3/4,RESET_SETUP_TICKS=CLK_HZ/100,
 parameter EVENT_DEPTH=8
)(input[1:0]button_valid,input[63:0]button_data,input clk,rst_n,input[1:0]enabled,force_reset,calibrate,express,mirror,
 input[3:0]layout_profile,input[1:0]scl_in,sda_in,int_n,
 input[1:0]wrist_enable,wrist_fresh,input[3:0]wrist_octaves,
 output[63:0]hit_snapshot_ticks,output[3:0]hit_actual_octaves,output[1:0]hit_used_snapshots,
 output[1:0]pose_samples,output[31:0]pose_pitches,
 output[1:0]scl_low,sda_low,reset_low,online,
 output[1535:0]diagnostic,output[511:0]status,output[95:0]report_rates,output[63:0]processing_overruns,
 output event_valid,input event_ready,output[63:0]event_data,
 output[1:0]release_pending,input[1:0]release_ack,
 output[63:0]epochs,event_drops,cancelled_events,output[1:0]cancel_now
);
 wire[1:0]sensor_restarted,note_on,velocity_update,push_valid,cancel;
 wire[7:0]hit_zone;wire[3:0]hit_profile,hit_octave,reason;
 wire[15:0]velocity,event_id;wire[63:0]payload;
 reg[1:0]previous_online,previous_enabled,previous_mirror;
 always @(posedge clk)begin
  if(!rst_n)begin previous_online<=0;previous_enabled<=0;previous_mirror<=mirror;end
  else begin previous_online<=online;previous_enabled<=enabled;previous_mirror<=mirror;end
 end
 assign cancel=sensor_restarted | force_reset | calibrate | (previous_online & ~online) |
  (previous_enabled & ~enabled) | (previous_mirror ^ mirror);
 assign cancel_now=cancel;
 genvar h;
 generate for(h=0;h<2;h=h+1)begin:hand
  mpu6050_hand #(.CLK_HZ(CLK_HZ),.HALF_DIV(HALF_DIV),.RESET_TICKS(RESET_TICKS),
   .BOOT_TICKS(BOOT_TICKS),.RESET_SETUP_TICKS(RESET_SETUP_TICKS)) endpoint(
   .snapshot_enable(wrist_enable[h]===1'b1),.stable_octave(wrist_octaves[h*2+:2]),.hit_snapshot_tick(hit_snapshot_ticks[h*32+:32]),.hit_actual_octave(hit_actual_octaves[h*2+:2]),.hit_used_snapshot(hit_used_snapshots[h]),.pose_sample(pose_samples[h]),.pose_pitch(pose_pitches[h*16+:16]),
   .clk(clk),.rst_n(rst_n),.enabled(enabled[h]),.force_reset(force_reset[h]),.calibrate(calibrate[h]),.express(express[h]),.mirror(mirror[h]),
   .layout_profile(layout_profile[h*2+:2]),.scl_in(scl_in[h]),.sda_in(sda_in[h]),.int_n(int_n[h]),
   .scl_low(scl_low[h]),.sda_low(sda_low[h]),.reset_low(reset_low[h]),.online(online[h]),
   .sensor_restarted(sensor_restarted[h]),.note_on(note_on[h]),.velocity_update(velocity_update[h]),
   .hit_zone(hit_zone[h*4+:4]),.hit_profile(hit_profile[h*2+:2]),.hit_octave(hit_octave[h*2+:2]),.trigger_reason(reason[h*2+:2]),
   .velocity(velocity[h*8+:8]),.event_id(event_id[h*8+:8]),.status(status[h*256+:256]),.diagnostic(diagnostic[h*768+:768]),
   .report_rates(report_rates[h*48+:48]),.processing_overruns(processing_overruns[h*32+:32]));
  assign push_valid[h]=enabled[h] && online[h] && !cancel[h] && button_valid[h];
  // Note-on has priority; the strength window completes before any next legal hit.
  // [31:30]kind 0=note-on,1=velocity; [29]hand; [28:25]zone; [24:23]layout;
  // [22:21]signed octave; [20:14]velocity; [13:12]trigger; [11:4]local event ID.
  assign payload[h*32+:32]={button_data[h*32+30+:2],h==1,button_data[h*32+:29]};
 end endgenerate
 two_hand_event_queue #(.DEPTH(EVENT_DEPTH)) events(.clk(clk),.rst_n(rst_n),.push_valid(push_valid),.push_payload(payload),
  .cancel(cancel),.release_ack(release_ack),.release_pending(release_pending),.epochs(epochs),
  .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),.drops(event_drops),.cancelled_events(cancelled_events));
endmodule
