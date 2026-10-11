`timescale 1ns/1ps
// Pin-level 0x08 reports at approximately 100Hz; actual 50MHz clocks,
// production calibration/freshness/quiet/hit windows, no injected DUT state.
module tb_i2c_path;
 reg clk=0;always #10 clk=!clk;
 reg rst_n=0,force_reset=0,calibrate=0;
 tri1 scl,sda;wire int_n,sck,cs_n,mosi,wake_n,sensor_rst_n,configured;
 assign scl=sck ? 1'b0 : 1'bz;assign sda=mosi ? 1'b0 : 1'bz;
 wire online,quat_valid,accel_valid,gyro_valid,gravity_valid,linear_valid,sensor_restarted;
 wire [1:0] accuracy;wire [4:0] feature_mask;
 wire signed [15:0] qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z;
 wire calibrated,calibrating,pose_valid;
 wire signed [15:0] yaw,pitch,roll;
 wire [5:0] calibration_progress;
 wire [1:0] calibration_state;
 wire [31:0] pose_overruns;
 reg [1:0] layout_profile=0;wire [1:0] hit_profile;wire [3:0] selected_zone,hit_zone;
 wire out_of_range,drift_warning,data_fresh,playable,armed,note_on,velocity_update;
 wire [7:0] velocity,event_id;wire signed [1:0] hit_octave;
 wire [31:0] hit_count,processing_overruns;
 wire linear_timestamp_valid;wire [31:0] linear_timestamp_ticks;wire [7:0] linear_sequence;
 wire signed [15:0] lx,ly,lz;wire [1:0] last_trigger_reason;wire signed [15:0] downward_accel;wire [6:0] hit_mask;
 bno_i2c_host #(.RESET_TICKS(100),.BOOT_TICKS(100),.RESET_SETUP_TICKS(100),.HALF_DIV(100)) host(
  .clk(clk),.rst_n(rst_n),.force_reset(force_reset),.miso(sda),.scl_in(scl),.int_n(int_n),
  .sck(sck),.cs_n(cs_n),.mosi(mosi),.wake_n(wake_n),.sensor_rst_n(sensor_rst_n),
  .online(online),.feature_mask(feature_mask),.sensor_restarted(sensor_restarted),
  .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),
  .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),
  .linear_ready(1'b1),.linear_valid(linear_valid),.linear_sequence(linear_sequence),
  .linear_timestamp_valid(linear_timestamp_valid),.linear_timestamp_ticks(linear_timestamp_ticks),.lx(lx),.ly(ly),.lz(lz),
  .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
  .gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z));
 bno_i2c_sensor_model peer(.*);
 quaternion_pose pose(.clk(clk),.rst_n(rst_n),.sensor_restarted(sensor_restarted),.online(online),.calibrate(calibrate),
  .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.gx(gx),.gy(gy),.gz(gz),
  .calibrated(calibrated),.calibrating(calibrating),.pose_valid(pose_valid),.yaw(yaw),.pitch(pitch),.roll(roll),
  .calibration_progress(calibration_progress),.calibration_state(calibration_state),.overruns(pose_overruns));
 gesture_control gestures(.*);
 imu_ui_feedback feedback(.clk(clk),.rst_n(rst_n),.clear(!online || sensor_restarted),.hit_valid(note_on),.hit_zone(hit_zone),.hit_mask(hit_mask));
 task report(input integer angle,input integer accel,input integer gyro);
  reg signed [15:0] z,w;
  begin
   z=$rtoi(16384*$sin(angle*3.141592653589793/360));w=$rtoi(16384*$cos(angle*3.141592653589793/360));
   peer.sensor_report(0,0,z,w,accel,gyro);
   #8600000; // approximately 10.3ms between samples, deliberately >10ms
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;wait(configured);wait(feature_mask==31);
  report(0,2510,0);if(!online)$fatal(1,"100Hz native reports did not make host online");
  @(negedge clk);calibrate=1;@(negedge clk);calibrate=0;
  peer.pose_accuracy=0;
  repeat(25)report(0,2510,0);
  if(!online || !calibrating || calibrated || calibration_progress!=0 || calibration_state!=1 || hit_count!=0)
   $fatal(1,"board symptom: online quality0 must explain blocked origin and suppress hits");
  peer.pose_accuracy=3;
  repeat(53)report(0,2510,0);
  if(!calibrated || calibrating || !data_fresh || !armed || pose_overruns || processing_overruns)
   $fatal(1,"100Hz calibration/arming failed cal=%b fresh=%b armed=%b",calibrated,data_fresh,armed);
  report(12,2510,0);report(25,2510,0);report(51,2510,0);report(51,2510,0);
  repeat(3)report(51,2510,0);
  if(selected_zone!=5 || !armed || yaw<50*16 || yaw>52*16)$fatal(1,"native report did not select LA");
  // Establish gyro before the independently parsed accel strike record.
  report(51,2510,512);report(51,1486,512);
  if(hit_count!=1 || hit_zone!=5 || !hit_mask[5] || velocity==0 || event_id!=1)
   $fatal(1,"native reports did not produce LA feedback");
  #45000000;
  if(playable || armed || hit_mask!=0)$fatal(1,"stale data did not protect/clear feedback");
  $display("TB_PASS native I2C 0x08 at 100Hz, production 50MHz windows, online quality0 blocked with reason, quality recovery and stable origin, yaw selects LA, strike flashes UI, stale suppression");$finish;
 end
 initial begin #2000000000;$fatal(1,"compatibility path timeout");end
endmodule
