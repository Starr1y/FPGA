`timescale 1ns/1ps
module tb_z_strike;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,sensor_restarted=0,online=1,calibrated=1,calibrating=0;
 reg [1:0] accuracy=3,layout_profile=0;
 reg pose_valid=0,accel_valid=0,gyro_valid=0,gravity_valid=0,linear_valid=0,linear_timestamp_valid=1;
 reg [7:0] linear_sequence=0;reg [31:0] linear_timestamp_ticks=0;
 reg signed [15:0] yaw=0,pitch=0,roll=0,lx=0,ly=0,lz=0,ax=0,ay=0,az=2510,gx=0,gy=0,gz=0;
 reg signed [15:0] gravity_x=0,gravity_y=0,gravity_z=2510;
 wire [3:0] selected_zone,hit_zone;wire [1:0] hit_profile,last_trigger_reason;
 wire out_of_range,drift_warning,data_fresh,playable,armed,note_on,velocity_update;
 wire [7:0] velocity,event_id;wire signed [1:0] hit_octave;
 wire [31:0]hit_count,processing_overruns;wire signed [15:0]downward_accel;
 gesture_control #(.CLK_HZ(100000)) dut(.*);
 integer pulses=0;always @(posedge clk)if(note_on)pulses++;
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 task sample(input integer down,input integer dt);
  begin
   lz=-down;linear_timestamp_ticks+=dt;linear_sequence++;
   pose_valid=1;gyro_valid=1;linear_valid=1;tick(1);
   pose_valid=0;gyro_valid=0;linear_valid=0;tick(dt*10-1);
  end
 endtask
 task quiet;begin repeat(14)sample(0,100);if(!armed || !data_fresh)$fatal(1,"not rearmed");end endtask
 task restart;begin sensor_restarted=1;tick(1);sensor_restarted=0;quiet();end endtask
 integer before_hits,n;
 initial begin
  tick(5);rst_n=1;quiet();
  // Raw gravity, tilt or non-Z translation cannot count as a linear Z hit.
  ax=32767;ay=-32768;az=32767;gravity_x=2200;gravity_y=0;gravity_z=1200;
  lx=1200;ly=-1200;repeat(5)sample(0,100);
  if(hit_count)$fatal(1,"raw gravity or XY caused a Z hit");
  lx=0;ly=0;
  // Acceleration alone: slow ramp never reaches 80 m/s^3; gyro remains zero.
  for(n=1;n<=10;n++)sample(n*64,100);
  if(hit_count!=1 || last_trigger_reason!=1 || hit_zone!=3 || gx!=0)$fatal(1,"acceleration-only/no wrist turn failed T%0d",last_trigger_reason);
  repeat(20)sample(768,100);if(hit_count!=1)$fatal(1,"held acceleration retriggered");
  quiet();
  sample(256,100);if(hit_count!=2 || last_trigger_reason!=2)$fatal(1,"jerk-only failed");
  quiet();sample(1024,100);if(hit_count!=3 || last_trigger_reason!=3)$fatal(1,"OR double counted/both failed");
  quiet();before_hits=hit_count;
  // Positive Z acceleration, and further positive Z jerk, cannot trigger.
  for(n=1;n<=10;n++)sample(-n*64,100);
  if(hit_count!=before_hits)$fatal(1,"positive Z acceleration/jerk triggered");
  // Negative Z jerk is independent: current lz remains positive throughout.
  sample(-128,100);
  if(hit_count!=before_hits+1 || last_trigger_reason!=2 || lz<=0)
   $fatal(1,"negative jerk with still-positive acceleration blocked");
  quiet();before_hits=hit_count;
  // Exact negative jerk threshold at az=0 is also independent of accel.
  sample(-128,50);sample(0,50);
  if(hit_count!=before_hits+1 || last_trigger_reason!=2 || lz!=0)
   $fatal(1,"negative jerk at zero acceleration blocked");
  quiet();before_hits=hit_count;
  quiet();repeat(10)begin sample(32,20);sample(0,20);end
  if(hit_count!=before_hits)$fatal(1,"subthreshold jerk noise triggered");
  // dt changes the derivative: 1 m/s^2 in 20ms is below threshold; 5ms is above.
  restart();before_hits=hit_count;sample(256,200);
  if(hit_count!=before_hits)$fatal(1,"slow jerk incorrectly triggered");
  quiet();sample(256,50);if(hit_count!=before_hits+1 || last_trigger_reason!=2)$fatal(1,"fast jerk dt failed");
  // Exact threshold equality; sequence and time wrap are modulo arithmetic.
  restart();linear_timestamp_ticks=32'hfffffeac;linear_sequence=254;repeat(4)sample(0,100);
  sample(128,50);if(last_trigger_reason!=2)$fatal(1,"jerk threshold equality or wrap failed");
  quiet();before_hits=hit_count;linear_sequence--;sample(1024,100);
  if(hit_count!=before_hits || data_fresh)$fatal(1,"duplicate report generated event");
  quiet();linear_sequence++;before_hits=hit_count;sample(1024,100);
  if(hit_count!=before_hits || data_fresh)$fatal(1,"sequence gap generated event");
  quiet();before_hits=hit_count;sample(1024,0);
  if(hit_count!=before_hits || data_fresh)$fatal(1,"zero dt generated event");
  quiet();sample(1024,401);if(hit_count!=before_hits)$fatal(1,"long dt generated event");
  quiet();linear_timestamp_valid=0;sample(1024,100);
  if(hit_count!=before_hits || data_fresh)$fatal(1,"missing timestamp generated event");
  linear_timestamp_valid=1;quiet();tick(5000);sample(1024,100);
  if(hit_count!=before_hits)$fatal(1,"stale history generated event");
  restart();before_hits=hit_count;accuracy=1;sample(1024,100);
  if(hit_count!=before_hits || playable)$fatal(1,"low quality triggered");
  accuracy=3;quiet();yaw=1441;sample(1024,100);
  if(hit_count!=before_hits || playable)$fatal(1,"out-of-fan triggered");
  yaw=0;restart();before_hits=hit_count;calibrating=1;sample(1024,100);
  if(hit_count!=before_hits)$fatal(1,"origin reset generated event");
  calibrating=0;quiet();layout_profile=1;sample(1024,100);
  if(hit_count!=before_hits)$fatal(1,"layout switch generated event");
  quiet();before_hits=hit_count;sample(32768,100);
  if(downward_accel!=32767 || hit_count!=before_hits+1)$fatal(1,"signed -32768 overflow");
  tick(5);if(pulses!=hit_count)$fatal(1,"event pulse/count mismatch");
  $display("TB_PASS local -Z acceleration OR timestamped directional jerk; no wrist-turn gate; independent negative jerk with positive/zero acceleration; gravity/XY/positive Z/noise/held-hit blocked; dt/sequence/wrap/stale/origin/layout/quality/range/signed guards");$finish;
 end
 initial begin #20000000;$fatal(1,"Z strike watchdog");end
endmodule
