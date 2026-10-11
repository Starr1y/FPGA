`timescale 1ns/1ps
module tb_fan_control;
 reg clk=0;always #5 clk=!clk;
 reg rst_n=0,sensor_restarted=0,online=1,calibrated=1,calibrating=0;
 reg [1:0] accuracy=3,layout_profile=0;
 reg pose_valid=0,accel_valid=0,gyro_valid=0,gravity_valid=0;
 reg signed [15:0] yaw=0,pitch=0,roll=0,ax=0,ay=0,az=-2510,gx=0,gy=0,gz=0,gravity_x=0,gravity_y=0,gravity_z=-2510;
 reg linear_valid=0,linear_timestamp_valid=1;reg [7:0]linear_sequence=0;reg [31:0]linear_timestamp_ticks=0;
 reg signed [15:0] lx=0,ly=0,lz=0;wire [1:0]last_trigger_reason;
 wire [3:0]selected_zone,hit_zone;wire [1:0]hit_profile;
 wire out_of_range,drift_warning,data_fresh,playable,armed,note_on,velocity_update;
 wire [7:0]velocity,event_id;wire signed [1:0]hit_octave;
 wire [31:0]hit_count,processing_overruns;wire signed [15:0]downward_accel;
 gesture_control #(.CLK_HZ(1000000),.QUIET_TICKS(4),.REFRACTORY_TICKS(8),.STRENGTH_TICKS(4)) dut(.*);
 wire [11:0]hit_mask;reg clear=0;
 imu_ui_feedback #(.CLK_HZ(1000),.HOLD_MS(100),.ZONES(12)) feedback(.clk(clk),.rst_n(rst_n),.clear(clear),.hit_valid(note_on),.hit_zone(hit_zone),.hit_mask(hit_mask));
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 task pose(input integer angle);begin yaw=angle;pose_valid=1;gyro_valid=1;gravity_valid=1;@(negedge clk);pose_valid=0;gyro_valid=0;gravity_valid=0;tick(2);end endtask
 task accel;begin linear_valid=1;linear_sequence++;linear_timestamp_ticks+=100;accel_valid=1;gyro_valid=1;gravity_valid=1;@(negedge clk);linear_valid=0;accel_valid=0;gyro_valid=0;gravity_valid=0;tick(8);end endtask
 integer p,z,n,c,lo,hi;
 initial begin
 tick(4);rst_n=1;gx=2000;
 for(p=0;p<3;p++)begin
 layout_profile=p;tick(2);n=p==1 ? 5 : p==2 ? 12 : 7;
 for(z=0;z<n;z++)begin
 lo=dut.zone_cut(p,z);hi=dut.zone_cut(p,z+1);c=(lo+hi)/2;pose(c);
 if(selected_zone!=z || out_of_range || drift_warning)$fatal(1,"profile %0d zone %0d center %0d selected %0d",p,z,c,selected_zone);
 if(z<n-1)begin
 pose(hi+47);if(selected_zone!=z)$fatal(1,"upper hysteresis failed");
 pose(hi+48);if(selected_zone!=z+1)$fatal(1,"upper boundary did not change");
 pose(hi-47);if(selected_zone!=z+1)$fatal(1,"lower hysteresis failed");
 pose(hi-48);if(selected_zone!=z)$fatal(1,"lower boundary did not change");end
 end
 pose(1440);if(out_of_range || selected_zone!=n-1)$fatal(1,"right endpoint invalid");
 pose(1441);if(!out_of_range || playable || selected_zone!=n-1)$fatal(1,"right endpoint wrapped");
 pose(-1441);if(!out_of_range || playable)$fatal(1,"left outside playable");
 pose(-1440);if(out_of_range || selected_zone!=0)$fatal(1,"left endpoint invalid");
 end
 pose(1320);gx=0;accel();tick(8);if(!armed)$fatal(1,"never armed");
 gx=0;lz=-1310;az=-1200;accel();tick(2);
 if(hit_count!=1 || hit_zone!=11 || hit_profile!=2 || !hit_mask[11])$fatal(1,"12th note hit or feedback truncated");
 layout_profile=1;tick(2);if(armed || note_on || hit_profile!=2 || hit_zone!=11)$fatal(1,"layout change generated/reinterpreted event");
 clear=1;tick(1);clear=0;if(hit_mask)$fatal(1,"feedback clear failed");
 sensor_restarted=1;tick(1);sensor_restarted=0;gx=0;pose(2864);pose(-2864);
 if(drift_warning)$fatal(1,"rear +/-180 crossing falsely latched drift");
 pose(-1600);if(!drift_warning)$fatal(1,"unsafe heading jump protection removed");
 $display("TB_PASS all 7/5/12 centers, bidirectional 3 degree hysteresis, noncyclic +/-90 endpoints, 12th accepted hit, profile event retention, feedback and rear yaw seam protection");$finish;
 end
 initial begin #100000;$fatal(1,"fan watchdog");end
endmodule
