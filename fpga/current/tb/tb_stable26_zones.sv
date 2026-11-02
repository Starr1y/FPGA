`timescale 1ns/1ps
module tb_stable26_zones;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,pv=0,lv=0,gv=0;reg signed[15:0]yaw=0;reg[1:0]profile=0;reg signed[15:0]pitch=0;integer k,n,expected;reg[3:0]before_zone;reg[7:0]seq=0;reg[31:0]ts=0;
wire[3:0]zone;wire fresh,playable,armed,note_on;
gesture_control #(.CLK_HZ(1000)) d(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.online(1'b1),.calibrated(1'b1),.calibrating(1'b0),.accuracy(2'd3),.layout_profile(profile),.pose_valid(pv),.yaw(yaw),.pitch(pitch),.roll(16'sd0),.accel_valid(lv),.gyro_valid(gv),.gravity_valid(1'b0),.linear_valid(lv),.linear_sequence(seq),.linear_timestamp_ticks(ts),.linear_timestamp_valid(1'b1),.lx(16'sd0),.ly(16'sd0),.lz(16'sd0),.ax(16'sd0),.ay(16'sd0),.az(16'sd0),.gx(16'sd2000),.gy(16'sd0),.gz(16'sd0),.gravity_x(16'sd0),.gravity_y(16'sd0),.gravity_z(16'sd0),.selected_zone(zone),.data_fresh(fresh),.playable(playable),.armed(armed),.note_on(note_on));
task frame(input integer angle);begin
 @(negedge clk);yaw=angle*16;pv=1;lv=1;gv=1;seq=seq+1;ts=ts+50;
 @(negedge clk);pv=0;lv=0;gv=0;repeat(3)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 for(k=0;k<3;k=k+1)begin
  profile=k;repeat(12)frame(0);n=k==0 ? 7 : k==1 ? 5 : 12;
  repeat(12)frame(-90);if(zone!=0)$fatal(1,"negative90 endpoint");
  repeat(12)frame(-45);expected=45*n/180;if(zone!=expected)$fatal(1,"negative45 symmetry");
  repeat(12)frame(-20);expected=70*n/180;if(zone!=expected)$fatal(1,"negative20");
  repeat(12)frame(0);if((k!=2 && zone!=n/2) || (k==2 && zone!=5 && zone!=6))$fatal(1,"center");
  before_zone=zone;pitch=45*16;repeat(12)frame(0);pitch=-45*16;repeat(12)frame(0);
  if(zone!=before_zone)$fatal(1,"pure pitch changed zone");pitch=0;
  repeat(12)frame(20);expected=k==1 ? 2 : 110*n/180;if(zone!=expected)$fatal(1,"positive20");
  repeat(12)frame(45);expected=135*n/180;if(zone!=expected)$fatal(1,"positive45");
  repeat(12)frame(90);if(zone!=n-1)$fatal(1,"positive90 endpoint");
  repeat(40)@(negedge clk);if(zone!=n-1 || playable)$fatal(1,"stale changed selected zone");
 end
 $display("TB_PASS 7/5/12 zone symmetric endpoints,20/45deg,pure pitch,stale display retention");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule

