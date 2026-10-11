`timescale 1ns/1ps
// Accelerated digital soak, not physical recognition rate or DAC latency evidence.
module tb_z_repeated;
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
 task quiet;begin repeat(14)sample(0,100);if(!armed || !data_fresh)$fatal(1,"soak did not rearm");end endtask
 integer n,k,peak,reason,before_hits;
 initial begin
  tick(5);rst_n=1;quiet();
  for(n=0;n<1000;n++)begin
   before_hits=hit_count;
   // 1000 positive-axis/non-Z/subthreshold gestures must produce zero events.
   lx=3000;ly=-3000;
   for(k=1;k<=5;k++)sample(-k*64,100);
   for(k=4;k>=0;k--)sample(-k*64,100);
   sample(32,20);sample(0,20);lx=0;ly=0;
   if(hit_count!=before_hits)$fatal(1,"nonhit group %0d accepted",n);
   quiet();
   case(n%3)
    0:begin peak=1024;reason=3;sample(peak,100);end
    1:begin peak=256;reason=2;sample(peak,100);end
    2:begin peak=640;reason=1;for(k=1;k<=10;k++)sample(k*64,100);end
   endcase
   if(hit_count!=before_hits+1 || last_trigger_reason!=reason || hit_zone!=3 ||
      event_id!=((n+1)%256) || velocity<32 || velocity>127)
    $fatal(1,"hit %0d lost/duplicated/wrong metadata",n);
   repeat(12)sample(peak,100);
   if(hit_count!=before_hits+1)$fatal(1,"sustained force repeated hit %0d",n);
   quiet();
  end
  tick(5);
  if(pulses!=1000 || hit_count!=1000 || processing_overruns!=0)
   $fatal(1,"soak final counters differ %0d %0d %0d",pulses,hit_count,processing_overruns);
  $display("TB_PASS 1000 simulated hits across T1/T2/T3, 1000 positive-axis/XY/subthreshold nonhit groups, held acceleration no retrigger, event-id wrap, counters; accelerated digital soak only");
  $finish;
 end
 initial begin #900000000;$fatal(1,"Z repeated watchdog");end
endmodule
