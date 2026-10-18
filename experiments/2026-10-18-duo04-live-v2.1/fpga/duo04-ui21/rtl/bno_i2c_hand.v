// One autonomous hand endpoint. All sample state and origins belong to this instance.
// Low-control outputs connect to external open-drain pads; no physical pins assigned here.
module bno_i2c_hand #(
 parameter CLK_HZ=50000000, HALF_DIV=100,
 parameter RESET_TICKS=CLK_HZ/100, BOOT_TICKS=CLK_HZ*3/4,
 parameter RESET_SETUP_TICKS=CLK_HZ/100
)(
 input clk,rst_n,enabled,force_reset,calibrate,express,mirror,
 input [1:0] layout_profile,input scl_in,sda_in,int_n,
 output scl_low,sda_low,reset_low,
 output online,sensor_restarted,note_on,velocity_update,
 output [3:0]hit_zone,output[1:0]hit_profile,hit_octave,trigger_reason,
 output[7:0]velocity,event_id,output[255:0]status,
 output[47:0]report_rates,output[31:0]processing_overruns
);
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
 wire signed[15:0]qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz;
 wire signed[15:0]yaw,pitch,roll,bend,vibrato,downward_accel;
 wire signed[15:0]mapped_yaw=mirror ? -yaw : yaw;
 wire signed[15:0]mapped_roll=mirror ? -roll : roll;
 wire [1:0]accuracy,calibration_state;wire[5:0]calibration_progress;
 wire [3:0]selected_zone;wire[7:0]brightness;wire[31:0]hit_count,protocol_errors,reset_attempts;
 wire [15:0]received_packets,received_bytes,pose_hz,accel_hz,gyro_hz;
 wire [31:0]pose_overruns,gesture_overruns;
 // A disabled/faulted endpoint releases every output. This is logical gating,
 // not a substitute for supply supervision or hardware power-off isolation.
 assign scl_low=enabled && rst_n && !fault && raw_scl;
 assign sda_low=enabled && rst_n && !fault && raw_sda;
 assign reset_low=enabled && rst_n && !fault && !raw_reset;
 bno_i2c_host #(.REPORT_BACKPRESSURE(1),.CLK_HZ(CLK_HZ),.HALF_DIV(HALF_DIV),
  .RESET_TICKS(RESET_TICKS),.BOOT_TICKS(BOOT_TICKS),.RESET_SETUP_TICKS(RESET_SETUP_TICKS)) host(
  .clk(clk),.rst_n(local_rst_n),.force_reset(force_reset),.miso(sda_in),.scl_in(scl_in),.int_n(int_n),
  .sck(raw_scl),.mosi(raw_sda),.sensor_rst_n(raw_reset),.fault_latched(fault),
  .online(online),.sensor_restarted(sensor_restarted),.linear_ready(1'b1),
  .quat_valid(quat_valid),.quat_sequence(quat_sequence),.quat_timestamp_ticks(quat_timestamp),.quat_timestamp_valid(quat_timestamp_valid),
  .qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),
  .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),
  .linear_sequence(linear_sequence),.linear_timestamp_ticks(linear_timestamp),.linear_timestamp_valid(linear_timestamp_valid),
  .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(lz),
  .pose_hz(pose_hz),.accel_hz(accel_hz),.gyro_hz(gyro_hz),.protocol_errors(protocol_errors),.reset_attempts(reset_attempts),
  .received_packets(received_packets),.received_bytes(received_bytes));
 quaternion_pose #(.CLK_HZ(CLK_HZ)) pose(
  .clk(clk),.rst_n(local_rst_n),.sensor_restarted(sensor_restarted),.online(online),.calibrate((calibrate || mirror_changed) && online),
  .quat_valid(quat_valid),.quat_sequence(quat_sequence),.quat_timestamp_ticks(quat_timestamp),.quat_timestamp_valid(quat_timestamp_valid),
  .qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.gx(gx),.gy(gy),.gz(gz),
  .calibrated(calibrated),.calibrating(calibrating),.calibration_progress(calibration_progress),.calibration_state(calibration_state),
  .pose_valid(pose_valid),.yaw(yaw),.pitch(pitch),.roll(roll),.overruns(pose_overruns),
  .pose_sequence(pose_sequence),.pose_timestamp_ticks(pose_timestamp),.pose_timestamp_valid(pose_timestamp_valid));
 gesture_control #(.CLK_HZ(CLK_HZ)) gesture(
  .clk(clk),.rst_n(local_rst_n),.sensor_restarted(sensor_restarted),.online(online),.calibrated(calibrated),.calibrating(calibrating),
  .accuracy(accuracy),.layout_profile(layout_profile),.pose_valid(pose_valid),.yaw(mapped_yaw),.pitch(pitch),.roll(mapped_roll),
  .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),
  .linear_sequence(linear_sequence),.linear_timestamp_ticks(linear_timestamp),.linear_timestamp_valid(linear_timestamp_valid),
  .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(lz),
  .selected_zone(selected_zone),.out_of_range(out_of_range),.drift_warning(drift_warning),.data_fresh(data_fresh),.playable(playable),.armed(armed),
  .note_on(note_on),.velocity_update(velocity_update),.velocity(velocity),.hit_zone(hit_zone),.hit_profile(hit_profile),.hit_octave(hit_octave),
  .hit_count(hit_count),.event_id(event_id),.last_trigger_reason(trigger_reason),.downward_accel(downward_accel),.processing_overruns(gesture_overruns));
 wire expression_sample,expression_reset;wire signed[15:0]expression_roll,expression_pitch;
 expression_stream_guard #(.CLK_HZ(CLK_HZ),.POSE_HZ(100)) cadence(
  .clk(clk),.rst_n(local_rst_n),.clear(sensor_restarted || calibrating || !online || mirror_changed),.enabled(calibrated && data_fresh && accuracy>=2),
  .pose_valid(pose_valid),.roll(mapped_roll),.pitch(pitch),.pose_sequence(pose_sequence),.pose_timestamp_ticks(pose_timestamp),.pose_timestamp_valid(pose_timestamp_valid),
  .sample_valid(expression_sample),.sample_roll(expression_roll),.sample_pitch(expression_pitch),.stream_reset(expression_reset));
 hand_expression #(.POSE_HZ(100)) expression(
  .clk(clk),.rst_n(local_rst_n),.sensor_restarted(sensor_restarted),.playable(playable),.express(express),.stream_reset(expression_reset),
  .pose_valid(expression_sample),.roll(expression_roll),.pitch(expression_pitch),.bend_cents(bend),.vibrato_cents(vibrato),.brightness(brightness),.expression_active(expression_active));
 assign status={reset_attempts,protocol_errors,received_bytes,received_packets,hit_count,
  velocity,brightness,vibrato,bend,mapped_roll,pitch,mapped_yaw,
  fault,expression_active,trigger_reason,hit_profile,hit_zone,selected_zone,calibration_progress,calibration_state,accuracy,
  data_fresh,drift_warning,out_of_range,playable,armed,calibrating,calibrated,online};
 assign report_rates={gyro_hz,accel_hz,pose_hz};
 assign processing_overruns=pose_overruns+gesture_overruns;
endmodule
