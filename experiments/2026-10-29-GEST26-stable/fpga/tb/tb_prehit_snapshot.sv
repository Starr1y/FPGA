`timescale 1ns/1ps
module tb_prehit_snapshot;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,clear=0,pv=0,ok=1,request=0;
 reg[31:0]pt=0,et=0;reg[3:0]zone=0;reg[1:0]octave=0,profile=0;
 wire busy,done,valid;wire[3:0]sz;wire[1:0]so,sp;wire[31:0]st,overruns;
 prehit_snapshot d(clk,rst_n,clear,pv,ok,pt,zone,octave,profile,request,et,busy,done,valid,sz,so,sp,st,overruns);
 task put(input[31:0]stamp,input[3:0]z,input[1:0]o);begin
  @(negedge clk);pv=1;pt=stamp;zone=z;octave=o;@(negedge clk);pv=0;
 end endtask
 task get(input[31:0]stamp,input bit expected,input[31:0]picked,input[3:0]z,input[1:0]o);begin
  @(negedge clk);et=stamp;request=1;@(negedge clk);request=0;
  wait(done);@(negedge clk);
  if(valid!==expected || (expected && (st!==picked || sz!==z || so!==o)))$fatal(1,"snapshot mismatch stamp=%d actual=%d zone=%d octave=%d",stamp,st,sz,so);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  put(1000,1,2);put(1050,2,3);put(1100,3,0);put(1150,4,1);
  get(1400,1,1100,3,0); // newest at least 30ms before strike
  put(1050,9,1);get(1400,1,1100,3,0); // late/duplicate cannot rewrite history
  get(2000,0,0,0,0); // older than80ms
  @(negedge clk);clear=1;@(negedge clk);clear=0;get(1450,0,0,0,0);
  put(32'hffffff00,6,2);put(32'hffffff80,5,3);get(32'hb0,1,32'hffffff80,5,3); // wrap
  @(negedge clk);clear=1;@(negedge clk);clear=0;ok=0;put(50,4,0);get(400,0,0,0,0);
  $display("TB_PASS prehit coherent pairing, 30/80ms, out-of-order, epoch, wrap, invalid");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
