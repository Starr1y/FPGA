`timescale 1ns/1ps
`include "tb/mpu6050_peer.sv"
module tb_mpu_host;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,force_reset=0,connected=1;tri1 scl,sda;wire low_scl,low_sda,online,configured,fault_latched,quat_valid,linear_valid;wire[1:0]accuracy;
 wire signed[15:0]qw,ax,az,lz,gz;wire[31:0]protocol_errors;integer reports=0;
 assign scl=low_scl ? 0 : 1'bz;assign sda=low_sda ? 0 : 1'bz;
 mpu6050_peer peer(.scl(scl),.sda(sda),.connected(connected),.ax(-16'sd512),.ay(16'sd0),.az(16'sd4096),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0),.configured(configured));
 mpu6050_host #(.CLK_HZ(1000000),.HALF_DIV(2),.BOOT_TICKS(20),.BIAS_LOG2(3),.WARMUP_SAMPLES(20)) dut(
 .clk(clk),.rst_n(rst),.force_reset(force_reset),.miso(sda),.scl_in(scl),.int_n(1'b1),.linear_ready(1'b1),.quat_ready(1'b1),
 .sck(low_scl),.mosi(low_sda),.online(online),.fault_latched(fault_latched),.quat_valid(quat_valid),.linear_valid(linear_valid),.accuracy(accuracy),.qw(qw),.ax(ax),.az(az),.lz(lz),.gz(gz),.protocol_errors(protocol_errors));
 always @(posedge clk)if(quat_valid)begin reports<=reports+1;if(!linear_valid)$fatal(1,"sample signals not aligned");if(ax> -310 || ax< -320 || az<2500 || az>2520)$fatal(1,"MPU byte order/scaling ax%d az%d",ax,az);end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  wait(reports>=30);if(!online || !configured || accuracy!=2 || protocol_errors!=0)$fatal(1,"init/config/fusion readiness failed");
  connected=0;wait(!online);if(!fault_latched || protocol_errors==0)$fatal(1,"disconnect missing");
  connected=1;@(negedge clk);force_reset=1;@(negedge clk);force_reset=0;
  wait(reports>=60);if(!online || accuracy!=2)$fatal(1,"recovery failed");
  $display("TB_PASS MPU wire-level WHOAMI/reset/config readback/burst14 signed scaling/ready/disconnect/software reset recovery");$finish;
 end
 initial begin #30000000;$fatal(1,"watchdog state%d",dut.state);end
endmodule
