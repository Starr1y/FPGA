`timescale 1ns/1ps
`include "tb/reference/mpu_host_reference.v"
module tb_linkfix331;
reg clk=0;always #5 clk=~clk;reg rst_n=0;reg[7:0]who=8'h75;reg bus_fault=0,drdy=0;wire online,old_online;wire[31:0]resets,old_resets;wire[15:0]packets;wire[3:0]reason;
mpu6050_host #(.CLK_HZ(1000000),.BOOT_TICKS(10),.BIAS_LOG2(2),.WARMUP_SAMPLES(4)) d(.clk(clk),.rst_n(rst_n),.force_reset(1'b0),.miso(1'b1),.scl_in(1'b1),.int_n(1'b0),.linear_ready(1'b1),.quat_ready(1'b1),.online(online),.reset_attempts(resets),.received_packets(packets),.failure_reason(reason));
mpu6050_host_reference #(.CLK_HZ(1000000),.BOOT_TICKS(10),.BIAS_LOG2(2),.WARMUP_SAMPLES(4)) old(.clk(clk),.rst_n(rst_n),.force_reset(1'b0),.miso(1'b1),.scl_in(1'b1),.int_n(1'b0),.linear_ready(1'b1),.quat_ready(1'b1),.online(old_online),.reset_attempts(old_resets));
integer i;initial begin
repeat(5)@(negedge clk);rst_n=1;wait(online);repeat(1200000)@(negedge clk);
if(!online || resets!=0 || packets<220 || old_resets<1)$fatal(1,"compat/reproduction failed packets%0d resets%0d old%0d",packets,resets,old_resets);
bus_fault=1;repeat(12000)@(negedge clk);if(online || reason!=2)$fatal(1,"bus fault hidden");
rst_n=0;repeat(5)@(negedge clk);who=8'h68;bus_fault=0;rst_n=1;wait(online);repeat(42000)@(negedge clk);if(online || reason!=6 || packets!=0)$fatal(1,"normal68 ready protection changed");
rst_n=0;repeat(5)@(negedge clk);drdy=1;rst_n=1;wait(online);repeat(100000)@(negedge clk);if(!online || packets==0 || resets!=0)$fatal(1,"normal68 stopped");
$display("TB_PASS old75 periodic reset reproduced,new75 200Hz>1s stable,no timeout widening,bus failure retained,68 DATA_RDY timeout retained");$finish;end
initial begin #50000000;$fatal(1,"watchdog");end
endmodule
module mpu6050_registers #(parameter HALF_DIV=100,TIMEOUT=1)(input clk,rst_n,start,read_op,input[6:0]address,input[7:0]register_address,write_value,input[4:0]read_count,input scl_in,sda_in,output scl_low,sda_low,output reg busy,done,output reg[3:0]error,output reg[111:0]data);
reg[7:0]regs[0:255];integer i;assign scl_low=0;assign sda_low=0;
always @(posedge clk)begin
if(!rst_n)begin busy<=0;done<=0;error<=0;data<=0;for(i=0;i<256;i=i+1)regs[i]<=0;end
else begin done<=0;if(start)begin busy<=1;data<=0;error<=0;
if(read_op)begin
 if(register_address==8'h75)data<=tb_linkfix331.who;
 else if(register_address==8'h3a)data<=tb_linkfix331.drdy;
 else if(register_address==8'h3b)begin data<=112'h0000000000000000001000000000;if(tb_linkfix331.bus_fault)error<=2;end
 else data<=regs[register_address];
end else regs[register_address]<=write_value;
end else if(busy)begin busy<=0;done<=1;end end end
endmodule
