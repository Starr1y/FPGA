`timescale 1ns/1ps
`include "tb/mpu331_peer.sv"
module tb_linkfix331_pins;
reg clk=0;always #5 clk=~clk;reg rst_n=0,right_connected=1;tri1[1:0]scl,sda;wire[1:0]sl,dl,online;wire[31:0]packets;wire[63:0]resets;wire[7:0]reason;wire[31:0]header;
genvar h;generate for(h=0;h<2;h=h+1)begin:hand
assign scl[h]=sl[h]?0:1'bz;assign sda[h]=dl[h]?0:1'bz;
mpu6050_host #(.CLK_HZ(1000000),.HALF_DIV(2),.BOOT_TICKS(10),.BIAS_LOG2(2),.WARMUP_SAMPLES(4)) d(.clk(clk),.rst_n(rst_n),.force_reset(1'b0),.miso(sda[h]),.scl_in(scl[h]),.int_n(1'b0),.linear_ready(1'b1),.quat_ready(1'b1),.sck(sl[h]),.mosi(dl[h]),.online(online[h]),.received_packets(packets[h*16+:16]),.reset_attempts(resets[h*32+:32]),.failure_reason(reason[h*4+:4]),.failure_header(header[h*16+:16]));
end endgenerate
mpu331_peer #(.PERIOD_NS(50000),.WHO(8'h75),.DISABLE_DRDY(1)) left(.scl(scl[0]),.sda(sda[0]),.connected(1'b1),.ax(16'sd0),.ay(16'sd0),.az(16'sd4096),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0));
mpu331_peer #(.PERIOD_NS(50000)) right(.scl(scl[1]),.sda(sda[1]),.connected(right_connected),.ax(16'sd0),.ay(16'sd0),.az(16'sd4096),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0));
initial begin repeat(5)@(negedge clk);rst_n=1;wait(online==3);repeat(140000)@(negedge clk);
if(online!=3 || resets!=0 || packets[15:0]<20 || packets[31:16]<20)$fatal(1,"physical bus sampling unstable online%b packets%h resets%h",online,packets,resets);
right_connected=0;repeat(50000)@(negedge clk);if(online[1] || !online[0] || reason[7:4]==0)$fatal(1,"bus fault/isolation hidden");
if(header[31:24]!=8'h3a && header[31:24]!=8'h3b)$fatal(1,"failure register not latched %h",header);
$display("TB_PASS real I2C START/repeatedSTART/ACK14bytes:WHO75 noDRDY+68 standard,200Hz schedule,bus disconnect isolation,failure register capture");$finish;end
initial begin #10000000;$fatal(1,"watchdog online%b packets%h reasons%h",online,packets,reason);end
endmodule
