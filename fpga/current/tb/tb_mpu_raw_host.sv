`timescale 1ns/1ps
// Transaction boundary model. Separately validated byte-command sequencer
// remains a different test; this verifies host initialization and recovery.
module mpu_register_transaction(
 input clk,rst_n,start,read,input[6:0]device_address,input[7:0]register_address,write_value,input[4:0]read_count,
 output reg busy,done,output reg[3:0]failure,output reg[119:0]read_bytes,
 output request,output[2:0]command,output[7:0]write_data,input engine_done,engine_ack,input[3:0]engine_error,input[7:0]engine_data);
 assign request=0;assign command=0;assign write_data=0;
 reg[7:0]regs[0:127];reg bad_who=1,bad_config=0;integer delay_count,j,operations=0;reg rr;reg[7:0]addr,val;reg[4:0]cnt;
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;done<=0;failure<=0;read_bytes<=0;delay_count<=0;end
  else begin
   done<=0;
   if(start)begin
    if(busy)$fatal(1,"host issued overlapping register transaction");
    if(device_address!=7'h68)$fatal(1,"address");
    busy<=1;delay_count<=12;rr<=read;addr<=register_address;val<=write_value;cnt<=read_count;operations<=operations+1;
   end
   if(busy)begin
    if(delay_count>0)delay_count<=delay_count-1;
    else begin
     busy<=0;done<=1;failure<=0;read_bytes<=0;
     if(!rr)regs[addr]<=val;
     else if(addr==8'h75)read_bytes[7:0]<=bad_who ? 8'h67 : 8'h68;
     else if(addr==8'h3a)begin
      if(cnt!=15)$fatal(1,"sample must be one15byte burst");
      read_bytes<=120'h1f00_f3ff_1100_4d01_0020_feff_3412_01;
     end else read_bytes[7:0]<=bad_config ? regs[addr]^8'h01 : regs[addr];
    end
   end
  end
 end
endmodule
module tb_mpu_raw_host;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,interrupt=0;wire online,configured,valid;wire[31:0]stamp,now_tick,errors;wire[3:0]failure;
 wire signed[15:0]ax,ay,az,temp,gx,gy,gz;integer n;
 mpu6050_raw_host #(.CLK_HZ(10000),.HALF_DIV(1)) d(.clk(clk),.rst_n(rst_n),.force_reset(1'b0),.scl_in(1'b1),.sda_in(1'b1),.int_in(interrupt),.scl_low(),.sda_low(),.configured(configured),.online(online),.sample_valid(valid),.ax(ax),.ay(ay),.az(az),.temperature(temp),.gx(gx),.gy(gy),.gz(gz),.sample_tick(stamp),.timestamp_now(now_tick),.errors(errors),.samples(),.last_error(failure));
 task wait_config;begin wait(configured);@(negedge clk);end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(1200)@(negedge clk);
  if(configured || online || errors==0)$fatal(1,"WHO failure accepted");
  d.transaction.bad_who=0;d.transaction.bad_config=1;repeat(2600)@(negedge clk);
  if(configured || online || errors<2)$fatal(1,"configuration readback failure accepted");
  d.transaction.bad_config=0;wait_config();
  if(d.transaction.regs[8'h19]!=4 || d.transaction.regs[8'h1b]!=8 || d.transaction.regs[8'h1c]!=8 || d.transaction.regs[8'h37]!=32)$fatal(1,"wrong sampling config");
  n=now_tick;interrupt=1;repeat(5)@(negedge clk);interrupt=0;
  wait(valid);@(negedge clk);
  if(!online || ax!=16'h1234 || ay!=-2 || az!=8192 || temp!=333 || gx!=17 || gy!=-13 || gz!=31)$fatal(1,"burst decoding %h %h %h %h %h %h %h",ax,ay,az,temp,gx,gy,gz);
  if(stamp<n || stamp>n+4)$fatal(1,"timestamp should be acquisition edge");
  repeat(600)@(negedge clk);if(online || configured)$fatal(1,"missing INT retained old data");
  $display("TB_PASS MPU host WHO rejection,config readback rejection,retry,200Hz config,atomic signed burst,INT timestamp,stale shutdown");$finish;
 end
 initial begin #1000000;$fatal(1,"host timeout");end
endmodule

