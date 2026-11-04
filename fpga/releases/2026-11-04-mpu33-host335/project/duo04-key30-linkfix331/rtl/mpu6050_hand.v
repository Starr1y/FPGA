// One autonomous hand endpoint. All sample state and origins belong to this instance.
// Low-control outputs connect to external open-drain pads; no physical pins assigned here.
module mpu6050_hand #(
 parameter CLK_HZ=50000000, HALF_DIV=100,
 parameter RESET_TICKS=CLK_HZ/100, BOOT_TICKS=CLK_HZ*3/4,
 parameter RESET_SETUP_TICKS=CLK_HZ/100
)(
 input clk,rst_n,enabled,force_reset,calibrate,express,mirror,
 input [1:0] layout_profile,input scl_in,sda_in,int_n,
 input snapshot_enable,input[1:0]stable_octave,
 output reg[31:0]hit_snapshot_tick,output reg[1:0]hit_actual_octave,output reg hit_used_snapshot,
 output pose_sample,output signed[15:0]pose_pitch,
 output scl_low,sda_low,reset_low,
 output online,sensor_restarted,note_on,velocity_update,
 output [3:0]hit_zone,output[1:0]hit_profile,hit_octave,trigger_reason,
 output[7:0]velocity,event_id,output[255:0]status,
 output[767:0]diagnostic,output[47:0]report_rates,output[31:0]processing_overruns
);
 wire pose_ready;wire[31:0]report_clock;reg[31:0]last_pose_tick,stale_reports;reg pose_tick_seen;
 wire local_rst_n=rst_n && enabled;
 reg mirror_old;
 always @(posedge clk)if(!local_rst_n)mirror_old<=mirror;else mirror_old<=mirror;
 wire mirror_changed=mirror!=mirror_old;
 wire raw_scl,raw_sda,raw_reset,fault;
 wire quat_valid,quat_timestamp_valid,linear_valid,linear_timestamp_valid;
 wire accel_valid,gyro_valid,gravity_valid,pose_valid,calibrated,calibrating;
 wire armed,playable,out_of_range,drift_warning,data_fresh,expression_active;
 wire [7:0]quat_sequence,linear_sequence,pose_sequence;
 wire [31:0]quat_timestamp,linear_timestamp,pose_timestamp;wire pose_timestamp_valid;
 wire[31:0]pose_transport_age=report_clock-quat_timestamp;
 wire[31:0]linear_transport_age=report_clock-linear_timestamp;
 wire pose_admitted=quat_valid && quat_timestamp_valid && pose_transport_age<=200 && (!pose_tick_seen || $signed(quat_timestamp-last_pose_tick)>0);
 wire linear_admitted=linear_valid && linear_timestamp_valid && linear_transport_age<=400;
 wire signed[15:0]qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz;
 wire signed[15:0]yaw,pitch,roll,bend,vibrato,downward_accel;
 assign pose_sample=pose_valid;assign pose_pitch=pitch;
 wire signed[15:0]mapped_yaw=mirror ? -yaw : yaw;
 wire signed[15:0]mapped_roll=roll; // yaw direction is independent of roll expression
 wire [1:0]accuracy,calibration_state;wire[5:0]calibration_progress;
 wire [3:0]selected_zone;wire[7:0]brightness;wire[31:0]hit_count,protocol_errors,reset_attempts;
 wire[3:0]first_failure,last_failure;wire[15:0]failure_header;wire[1:0]failure_inputs;wire[4:0]features;
 wire[31:0]sequence_gaps;reg[31:0]age_pose,age_accel,age_gyro,age_linear;
 always @(posedge clk)begin
  if(!local_rst_n)begin last_pose_tick<=0;pose_tick_seen<=0;stale_reports<=0;age_pose<=32'hffffffff;age_accel<=32'hffffffff;age_gyro<=32'hffffffff;age_linear<=32'hffffffff;end
  else begin
   if(pose_admitted)begin last_pose_tick<=quat_timestamp;pose_tick_seen<=1;end
   if((quat_valid && !pose_admitted) || (linear_valid && !linear_admitted))stale_reports<=stale_reports+1'b1;
   if(sensor_restarted)pose_tick_seen<=0;
   if(pose_admitted)age_pose<=0;else if(age_pose!=32'hffffffff)age_pose<=age_pose+1'b1;
   if(accel_valid)age_accel<=0;else if(age_accel!=32'hffffffff)age_accel<=age_accel+1'b1;
   if(gyro_valid)age_gyro<=0;else if(age_gyro!=32'hffffffff)age_gyro<=age_gyro+1'b1;
   if(linear_admitted)age_linear<=0;else if(age_linear!=32'hffffffff)age_linear<=age_linear+1'b1;
  end
 end
 reg[31:0]rate_ticks,linear_interval,last_linear_stamp,hit_stamp;
 reg[15:0]linear_counter,linear_rate;reg linear_stamp_seen;
 wire [3:0]candidate_zone;wire signed[15:0]filtered_yaw;
 wire snap_busy,snap_done,snap_valid;wire[3:0]snap_zone;wire[1:0]snap_octave,snap_profile;
 wire[31:0]snap_tick,snap_overruns;
 reg[109:0]linear_delay;reg[7:0]pose_delay;reg[31:0]delayed_pose_stamp;
 reg signed[15:0]linear_z_q;reg[7:0]linear_seq_q;reg[31:0]linear_tick_q;reg linear_stamp_q;
 always @(posedge clk)begin
  if(!local_rst_n)begin
   rate_ticks<=0;linear_counter<=0;linear_rate<=0;linear_interval<=0;last_linear_stamp<=0;hit_stamp<=0;linear_stamp_seen<=0;hit_snapshot_tick<=0;hit_actual_octave<=0;hit_used_snapshot<=0;
   linear_delay<=0;pose_delay<=0;delayed_pose_stamp<=0;linear_z_q<=0;linear_seq_q<=0;linear_tick_q<=0;linear_stamp_q<=0;
  end else begin
   linear_delay<={linear_delay[108:0],linear_admitted};
   pose_delay<={pose_delay[6:0],pose_valid};if(pose_valid)delayed_pose_stamp<=pose_timestamp;
   if(rate_ticks==CLK_HZ-1)begin rate_ticks<=0;linear_rate<=linear_counter;linear_counter<=linear_valid ? 1 : 0;end
   else begin rate_ticks<=rate_ticks+1'b1;if(linear_valid && linear_counter!=65535)linear_counter<=linear_counter+1'b1;end
   if(linear_admitted && !snap_busy)begin
    linear_z_q<=lz;linear_seq_q<=linear_sequence;linear_tick_q<=linear_timestamp;linear_stamp_q<=linear_timestamp_valid;
    if(linear_stamp_seen)linear_interval<=linear_timestamp-last_linear_stamp;
    last_linear_stamp<=linear_timestamp;linear_stamp_seen<=1;
   end
   if(note_on)begin hit_stamp<=linear_tick_q;hit_snapshot_tick<=snap_tick;hit_actual_octave<=hit_octave;hit_used_snapshot<=snapshot_enable;end
   if(sensor_restarted)linear_stamp_seen<=0;
  end
 end
 prehit_snapshot history(.clk(clk),.rst_n(local_rst_n),.clear(!playable || calibrate || mirror_changed || sensor_restarted),
  .pose_valid(pose_delay[7]),.pose_ok(playable && pose_timestamp_valid),.pose_tick(delayed_pose_stamp),
  .zone(selected_zone),.octave(stable_octave),.profile(layout_profile),
  .request(linear_admitted),.event_tick(linear_timestamp),
  .busy(snap_busy),.done(snap_done),.valid(snap_valid),.selected_zone(snap_zone),.selected_octave(snap_octave),.selected_profile(snap_profile),.selected_tick(snap_tick),.overruns(snap_overruns));
 // Diagnostic bytes 74..95 extend GEST25's reserved area; no old fields move.
 assign diagnostic={8'd0,7'b0,(snapshot_enable && !snap_valid),filtered_yaw,hit_stamp,snap_tick,
  4'b0,candidate_zone,snap_profile,snap_octave,snap_zone,linear_interval,linear_rate,6'b0,mirror,snap_valid,8'd2,
  3'b0,features,6'b0,failure_inputs,failure_header,4'b0,last_failure,4'b0,first_failure,reset_attempts,sequence_gaps,lz,age_linear,age_gyro,age_accel,age_pose,processing_overruns,report_rates,status};

 wire [15:0]received_packets,received_bytes,pose_hz,accel_hz,gyro_hz;
 wire [31:0]pose_overruns,gesture_overruns;
 // A disabled/faulted endpoint releases every output. This is logical gating,
 // not a substitute for supply supervision or hardware power-off isolation.
 assign scl_low=enabled && rst_n && !fault && raw_scl;
 assign sda_low=enabled && rst_n && !fault && raw_sda;
 assign reset_low=enabled && rst_n && !fault && !raw_reset;
 mpu6050_host #(.REPORT_BACKPRESSURE(1),.CLK_HZ(CLK_HZ),.HALF_DIV(HALF_DIV),
  .RESET_TICKS(RESET_TICKS),.BOOT_TICKS(BOOT_TICKS),.RESET_SETUP_TICKS(RESET_SETUP_TICKS)) host(
  .clk(clk),.rst_n(local_rst_n),.force_reset(force_reset),.miso(sda_in),.scl_in(scl_in),.int_n(int_n),
  .sck(raw_scl),.mosi(raw_sda),.sensor_rst_n(raw_reset),.fault_latched(fault),
  .online(online),.sensor_restarted(sensor_restarted),.linear_ready(!snap_busy && linear_delay==0),.quat_ready(pose_ready),.timestamp_now(report_clock),
  .first_failure_reason(first_failure),.failure_reason(last_failure),.failure_header(failure_header),.failure_inputs(failure_inputs),.feature_mask(features),.sequence_gaps(sequence_gaps),
  .quat_valid(quat_valid),.quat_sequence(quat_sequence),.quat_timestamp_ticks(quat_timestamp),.quat_timestamp_valid(quat_timestamp_valid),
  .qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),
  .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),
  .linear_sequence(linear_sequence),.linear_timestamp_ticks(linear_timestamp),.linear_timestamp_valid(linear_timestamp_valid),
  .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(lz),
  .pose_hz(pose_hz),.accel_hz(accel_hz),.gyro_hz(gyro_hz),.protocol_errors(protocol_errors),.reset_attempts(reset_attempts),
  .received_packets(received_packets),.received_bytes(received_bytes));
 quaternion_pose #(.CLK_HZ(CLK_HZ)) pose(
  .clk(clk),.rst_n(local_rst_n),.sensor_restarted(sensor_restarted),.online(online),.calibrate((calibrate || mirror_changed) && online),
  .ready(pose_ready),.quat_valid(pose_admitted),.quat_sequence(quat_sequence),.quat_timestamp_ticks(quat_timestamp),.quat_timestamp_valid(quat_timestamp_valid),
  .qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.gx(gx),.gy(gy),.gz(gz),
  .calibrated(calibrated),.calibrating(calibrating),.calibration_progress(calibration_progress),.calibration_state(calibration_state),
  .pose_valid(pose_valid),.yaw(yaw),.pitch(pitch),.roll(roll),.overruns(pose_overruns),
  .pose_sequence(pose_sequence),.pose_timestamp_ticks(pose_timestamp),.pose_timestamp_valid(pose_timestamp_valid));
 gesture_control #(.CLK_HZ(CLK_HZ)) gesture(
  .clk(clk),.rst_n(local_rst_n),.sensor_restarted(sensor_restarted),.online(online),.calibrated(calibrated),.calibrating(calibrating),
  .accuracy(accuracy),.layout_profile(layout_profile),.snapshot_required(snapshot_enable),.snapshot_valid(snap_valid),.snapshot_zone(snap_zone),.snapshot_octave(snap_octave),.snapshot_profile(snap_profile),.filtered_yaw(filtered_yaw),.candidate_zone(candidate_zone),
  .pose_valid(pose_valid),.yaw(mapped_yaw),.pitch(pitch),.roll(mapped_roll),
  .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_delay[109]),
  .linear_sequence(linear_seq_q),.linear_timestamp_ticks(linear_tick_q),.linear_timestamp_valid(linear_stamp_q),
  .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(linear_z_q),
  .selected_zone(selected_zone),.out_of_range(out_of_range),.drift_warning(drift_warning),.data_fresh(data_fresh),.playable(playable),.armed(armed),
  .note_on(note_on),.velocity_update(velocity_update),.velocity(velocity),.hit_zone(hit_zone),.hit_profile(hit_profile),.hit_octave(hit_octave),
  .hit_count(hit_count),.event_id(event_id),.last_trigger_reason(trigger_reason),.downward_accel(downward_accel),.processing_overruns(gesture_overruns));
 wire expression_sample,expression_reset;wire signed[15:0]expression_roll,expression_pitch;
 expression_stream_guard #(.CLK_HZ(CLK_HZ),.POSE_HZ(200)) cadence(
  .clk(clk),.rst_n(local_rst_n),.clear(sensor_restarted || calibrating || !online || mirror_changed),.enabled(calibrated && data_fresh && accuracy>=2),
  .pose_valid(pose_valid),.roll(mapped_roll),.pitch(pitch),.pose_sequence(pose_sequence),.pose_timestamp_ticks(pose_timestamp),.pose_timestamp_valid(pose_timestamp_valid),
  .sample_valid(expression_sample),.sample_roll(expression_roll),.sample_pitch(expression_pitch),.stream_reset(expression_reset));
 hand_expression #(.POSE_HZ(200)) expression(
  .clk(clk),.rst_n(local_rst_n),.sensor_restarted(sensor_restarted),.playable(playable),.express(express),.stream_reset(expression_reset),
  .pose_valid(expression_sample),.roll(expression_roll),.pitch(expression_pitch),.bend_cents(bend),.vibrato_cents(vibrato),.brightness(brightness),.expression_active(expression_active));
 assign status={reset_attempts,protocol_errors,received_bytes,received_packets,hit_count,
  velocity,brightness,vibrato,bend,mapped_roll,pitch,mapped_yaw,
  fault,expression_active,trigger_reason,hit_profile,hit_zone,selected_zone,calibration_progress,calibration_state,accuracy,
  data_fresh,drift_warning,out_of_range,playable,armed,calibrating,calibrated,online};
 assign report_rates={gyro_hz,accel_hz,pose_hz};
 assign processing_overruns=pose_overruns+gesture_overruns+stale_reports+snap_overruns;
endmodule
