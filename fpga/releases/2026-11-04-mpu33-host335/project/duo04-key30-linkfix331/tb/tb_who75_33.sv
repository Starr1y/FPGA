`timescale 1ns/1ps
module tb_who75_33;
reg clk=0;always #5 clk=~clk;reg rst_n=0;integer id;
mpu6050_host #(.CLK_HZ(1000000)) d(.clk(clk),.rst_n(rst_n),.force_reset(1'b0),.miso(1'b1),.scl_in(1'b1),.int_n(1'b0),.linear_ready(1'b1),.quat_ready(1'b1));
initial begin
 for(id=0;id<256;id=id+1)begin
 rst_n=0;repeat(3)@(negedge clk);rst_n=1;
 force d.state=2;force d.data=id;@(posedge clk);#1;release d.state;release d.data;
 if(id==104 || id==117)begin if(d.failure_reason!=0 || d.after_transaction!=3 || !d.request)$fatal(1,"valid identity rejected %h",id);end
 else if(d.failure_reason!=4 || d.online)$fatal(1,"invalid identity accepted %h",id);
 end
 $display("TB_PASS all256 identity values:68/75 accepted,other254 rejected");$finish;end
endmodule
