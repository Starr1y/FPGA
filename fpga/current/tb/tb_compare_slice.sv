`timescale 1ns/1ps
module tb_compare_slice;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,flush=0,iv=0,oready=0;reg[1:0]cancel=0;
 reg[63:0]epochs=64'hfffffff8_fffffff8,data=0;
 wire ir,ov,rr,rv;wire[63:0]od,rd;
 event_register_slice d(clk,rst_n,flush,cancel,epochs,iv,ir,data,ov,oready,od);
 event_register_slice_v6_reference r(clk,rst_n,flush,cancel,epochs,iv,rr,data,rv,oready,rd);
 reg[11:0]a=0,b=0;wire ge;unsigned_ge12 cmp(a,b,ge);
 integer k;reg[31:0]random_state=32'hd2198ab7;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(k=0;k<100000;k=k+1)begin
   random_state=random_state*1664525+1013904223;
   iv=random_state[0];oready=random_state[4];flush=(k%107)==3;
   cancel=k%31==0 ? random_state[3:2] : 0;
   if(k%23==0)epochs[31:0]=epochs[31:0]+1;
   if(k%29==0)epochs[63:32]=epochs[63:32]+1;
   data={random_state[5] ? epochs[63:32] : epochs[31:0],random_state};data[29]=random_state[5];
   if(k%7==0)data[63:32]=data[63:32]-1;
   a=k<4096 ? k : random_state[11:0];
   case(k%5)0:b=a;1:b=a+1'b1;2:b=a-1'b1;3:b=0;default:b=random_state[23:12];endcase
   #1;if(ge!==(a>=b))$fatal(1,"12bit compare %d %d",a,b);
   if({ir,ov,od}!=={rr,rv,rd})$fatal(1,"combinational event slice mismatch %d",k);
   @(posedge clk);#1;
   if({ir,ov,od}!=={rr,rv,rd})$fatal(1,"registered event slice mismatch %d",k);
   @(negedge clk);
  end
  $display("TB_PASS100000 unsigned12 comparisons and cycle-exact event slices; current/stale epochs,32bitwrap,backpressure,flush,cancel");$finish;
 end
endmodule
// One event register with no combinational downstream-ready -> upstream-ready
// path. Epoch/cancel checks discard only the affected hand. Stop/source changes
// flush synchronously and suppress output immediately.
module event_register_slice_v6_reference(
 input clk,rst_n,flush,input[1:0]cancel,input[63:0]epochs,
 input in_valid,output in_ready,input[63:0]in_data,
 output out_valid,input out_ready,output[63:0]out_data);
 reg full;reg[63:0]data_q;
 wire dead=cancel[data_q[29]] || data_q[63:32]!=(data_q[29] ? epochs[63:32] : epochs[31:0]);
 assign in_ready=!full && !flush;
 assign out_valid=full && !flush && !dead;
 assign out_data=data_q;
 always @(posedge clk)begin
  if(!rst_n || flush)begin full<=0;data_q<=0;end
  else if(full)begin if(dead || out_ready)full<=0;end
  else if(in_valid)begin data_q<=in_data;full<=1;end
 end
endmodule
