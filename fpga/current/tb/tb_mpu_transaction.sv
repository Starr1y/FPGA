`timescale 1ns/1ps
module tb_mpu_transaction;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,read=1,edone=0,ack=1;reg[3:0]err=0;reg[7:0]data=0;
 wire busy,done,req;wire[3:0]failure;wire[119:0]bytes;wire[2:0]cmd;wire[7:0]wd;
 integer index=0,mode=0,j;reg[2:0]expected;
 mpu_register_transaction d(clk,rst_n,start,read,7'h68,8'h3a,8'h55,5'd15,busy,done,failure,bytes,req,cmd,wd,edone,ack,err,data);
 always @(negedge clk)begin
  edone=0;
  if(req)begin
   if(mode==0)begin
    case(index)0,4:expected=0;1,2,5:expected=2;3,21:expected=1;20:expected=4;default:expected=3;endcase
    if(cmd!==expected)$fatal(1,"command order index%0d cmd%0d expected%0d",index,cmd,expected);
    if(index==1 && wd!=8'hd0 || index==2 && wd!=8'h3a || index==5 && wd!=8'hd1)$fatal(1,"address bytes");
   end
   ack=!(mode==1&&index==1);err=(mode==2&&index==1)?13:0;
   if(cmd==3 || cmd==4)begin data=index-6;end
   edone=1;index=index+1;
  end
 end
 task go;begin @(negedge clk);start=1;@(negedge clk);start=0;wait(done);@(posedge clk);#1;end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;go();
  if(failure || index!=22)$fatal(1,"read completion");
  for(j=0;j<15;j=j+1)if(bytes[j*8+:8]!=j)$fatal(1,"burst byte%0d",j);
  mode=1;index=0;go();if(failure!=1||index!=3||cmd!=1)$fatal(1,"NACK did not stop");
  mode=2;index=0;go();if(failure!=13||index!=2)$fatal(1,"timeout not propagated");
  mode=3;index=0;read=0;go();if(failure || index!=5)$fatal(1,"write sequence");
  $display("TB_PASS MPU burst15,address order,finalNACK,STOP,write,addressNACK,stretch timeout");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
