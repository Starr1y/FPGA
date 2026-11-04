`timescale 1ns/1ps
module tb_stable25_zone;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,pv=0,lv=0,gv=0;reg signed[15:0]yaw=0;reg[7:0]seq=0;reg[31:0]ts=0;
wire[3:0]zone;wire fresh,playable,armed,note_on;
gesture_control #(.CLK_HZ(1000)) d(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.online(1'b1),.calibrated(1'b1),.calibrating(1'b0),.accuracy(2'd3),.layout_profile(2'd0),.pose_valid(pv),.yaw(yaw),.pitch(16'sd0),.roll(16'sd0),.accel_valid(lv),.gyro_valid(gv),.gravity_valid(1'b0),.linear_valid(lv),.linear_sequence(seq),.linear_timestamp_ticks(ts),.linear_timestamp_valid(1'b1),.lx(16'sd0),.ly(16'sd0),.lz(16'sd0),.ax(16'sd0),.ay(16'sd0),.az(16'sd0),.gx(16'sd2000),.gy(16'sd0),.gz(16'sd0),.gravity_x(16'sd0),.gravity_y(16'sd0),.gravity_z(16'sd0),.selected_zone(zone),.data_fresh(fresh),.playable(playable),.armed(armed),.note_on(note_on));
task frame(input integer angle);begin
 @(negedge clk);yaw=angle*16;pv=1;lv=1;gv=1;seq=seq+1;ts=ts+50;
 @(negedge clk);pv=0;lv=0;gv=0;repeat(3)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 repeat(12)frame(0);if(zone!=3 || !playable)$fatal(1,"center readiness");
 repeat(3)frame(80);if(zone!=3)$fatal(1,"unstable candidate accepted");
 repeat(12)frame(0);if(zone!=3)$fatal(1,"jitter switched zone");
 repeat(12)frame(80);if(zone!=6)$fatal(1,"multi-zone stable turn %d",zone);
 repeat(50)@(negedge clk);if(zone!=6 || playable || note_on)$fatal(1,"stale must retain zone but prohibit hit");
 $display("TB_PASS stable zone / jitter / multi-zone / stale protection");$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
