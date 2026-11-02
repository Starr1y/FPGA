`timescale 1ns/1ps
// Production 50MHz clock and divider, physical open-drain peer. No forced state.
module tb_mixed_latency;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,enabled=0,force_reset=0,calibrate=0;
 tri1 scl,sda,sensor_reset_n;wire int_n,configured,scl_low,sda_low,reset_low;
 wire online,sensor_restarted,note_on,velocity_update;
 wire[3:0]hit_zone;wire[1:0]hit_profile,hit_octave,trigger_reason;
 wire[7:0]velocity,event_id;wire[255:0]status;wire[47:0]report_rates;wire[31:0]processing_overruns;
 assign scl=scl_low ? 1'b0 : 1'bz;assign sda=sda_low ? 1'b0 : 1'bz;
 assign sensor_reset_n=reset_low ? 1'b0 : 1'bz;
 bno_i2c_hand #(.RESET_TICKS(5000),.BOOT_TICKS(50000),.RESET_SETUP_TICKS(5000)) dut(
  .clk(clk),.rst_n(rst_n),.enabled(enabled),.force_reset(force_reset),.calibrate(calibrate),.express(1'b1),.mirror(1'b0),
  .layout_profile(2'b0),.scl_in(scl),.sda_in(sda),.int_n(int_n),.scl_low(scl_low),.sda_low(sda_low),.reset_low(reset_low),
  .online(online),.sensor_restarted(sensor_restarted),.note_on(note_on),.velocity_update(velocity_update),
  .hit_zone(hit_zone),.hit_profile(hit_profile),.hit_octave(hit_octave),.trigger_reason(trigger_reason),.velocity(velocity),.event_id(event_id),
  .status(status),.report_rates(report_rates),.processing_overruns(processing_overruns));
 bno_mixed_peer peer(.sensor_rst_n(sensor_reset_n),.scl(scl),.sda(sda),.int_n(int_n),.configured(configured));
 integer linear_count=0,pose_count=0,gyro_count=0,aux_count=0,notes=0;
 reg[31:0]last_ltime=0,last_ptime=0;integer delta;
 realtime start_read=0,negative_time=0,max_linear=0,hit_latency=0,fall=0,rise=0,min_low=1e9,min_high=1e9;
 always @(negedge scl)begin
  if(rise!=0 && $realtime-rise<min_high)min_high=$realtime-rise;fall=$realtime;
 end
 always @(posedge scl)begin
  if(fall!=0 && $realtime-fall<min_low)min_low=$realtime-fall;rise=$realtime;
 end
 always @(posedge dut.linear_valid)begin
  linear_count++;
  if(dut.linear_sequence!==((linear_count-1)&255))$fatal(1,"linear sequence skipped");
  if(linear_count>1)begin delta=dut.linear_timestamp-last_ltime;if(delta<24 || delta>26)$fatal(1,"linear cadence %d",delta);end
  last_ltime=dut.linear_timestamp;
  if(!dut.linear_timestamp_valid)$fatal(1,"missing linear timestamp");
  if($realtime-start_read>max_linear)max_linear=$realtime-start_read;
 end
 always @(posedge dut.quat_valid)begin
  pose_count++;
  if(dut.quat_sequence!==((pose_count-1)&255))$fatal(1,"pose sequence skipped");
  if(pose_count>1)begin delta=dut.quat_timestamp-last_ptime;if(delta<49 || delta>51)$fatal(1,"pose cadence %d",delta);end
  last_ptime=dut.quat_timestamp;
 end
 always @(posedge dut.gyro_valid)gyro_count++;
 always @(posedge dut.accel_valid)aux_count++;
 always @(posedge note_on)begin notes++;hit_latency=$realtime-negative_time;end
 integer t;realtime began;
 initial begin
  repeat(6)@(negedge clk);rst_n=1;enabled=1;
  wait(configured);#2000000;
  for(t=0;t<160;t++)begin
   began=$realtime;start_read=began;
   // Withholding any rotation: negative-Z jerk must still trigger.
   if(t==140)negative_time=began;
   peer.mixed_report(t,t==140 ? -16'sd64 : 16'sd0);
   if(t==4)begin @(negedge clk);calibrate=1;@(negedge clk);calibrate=0;end
   #(2500000-($realtime-began));
   if(t==136 && (!status[1] || !status[3]))$fatal(1,"origin/playable not ready %h",status[31:0]);
  end
  if(linear_count!=160 || pose_count!=80 || gyro_count!=80 || aux_count!=20)$fatal(1,"missing reports L%0d P%0d G%0d A%0d",linear_count,pose_count,gyro_count,aux_count);
  if(notes!=1 || trigger_reason!=2 || processing_overruns || dut.protocol_errors || !online)$fatal(1,"directional note/error notes=%0d reason=%0d errs=%0d",notes,trigger_reason,dut.protocol_errors);
  if(hit_latency<=0 || hit_latency>2500000 || peer.max_transfer>2500000 || min_low<1300 || min_high<600)$fatal(1,"latency/bus limit");
  $display("TB_PASS mixed 400Hz linear/200Hz pose+gyro/50Hz auxiliary; no backlog,overrun,missing SH2 report sequences; calibration and pure negative-Z jerk; linear availability-to-decode max=%0.3fus report-to-note=%0.3fus largest transfer=%0.3fus min SCL low/high=%0.1f/%0.1fns",max_linear/1000,hit_latency/1000,peer.max_transfer/1000,min_low,min_high);
  @(negedge clk);enabled=0;#100;if(scl_low || sda_low || reset_low)$fatal(1,"disabled bus driven");$finish;
 end
 initial begin #600000000;$fatal(1,"timeout");end
endmodule
