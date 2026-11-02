`timescale 1ns/1ps
module tb_report_backpressure;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,packet_ready=0,qr=0,lr=0;reg[7:0]mem[0:63];wire[8:0]addr;
 wire take,qv,lv;wire[31:0]qt,lt,malformed;integer qc=0,lc=0,i;
 shtp_report_decode #(.REPORT_BACKPRESSURE(1)) d(.clk(clk),.rst_n(rst_n),.packet_ready(packet_ready),.packet_length(10'd43),
 .packet_hint_ticks(32'd1000),.packet_hint_valid(1'b1),.linear_ready(lr),.quat_ready(qr),.packet_take(take),.read_addr(addr),.read_data(mem[addr]),
 .quat_valid(qv),.linear_valid(lv),.quat_timestamp_ticks(qt),.linear_timestamp_ticks(lt),.malformed(malformed));
 always @(posedge clk)begin
  if(qv)begin qc=qc+1;if(qt!=1000)$fatal(1,"pose timestamp");end
  if(lv)begin lc=lc+1;if(lt!=1025)$fatal(1,"linear timestamp");end
 end
 initial begin
  for(i=0;i<64;i=i+1)mem[i]=0;
  mem[0]=43;mem[2]=3;mem[3]=1;mem[4]=8'hfb;
  mem[9]=8;mem[10]=1;mem[11]=3;mem[20]=64;
  mem[21]=8;mem[22]=2;mem[23]=3;mem[32]=64;
  mem[33]=4;mem[34]=1;mem[35]=3;mem[36]=25;
  repeat(4)@(negedge clk);rst_n=1;packet_ready=1;
  repeat(80)@(negedge clk);if(qc || lc)$fatal(1,"unready report was consumed");
  qr=1;wait(qv);@(negedge clk);qr=0;
  repeat(80)@(negedge clk);if(qc!=1 || lc)$fatal(1,"second pose bypassed backpressure");
  qr=1;wait(qc==2);repeat(80)@(negedge clk);if(lc)$fatal(1,"linear bypassed backpressure");
  lr=1;wait(take);@(negedge clk);packet_ready=0;
  if(qc!=2 || lc!=1 || malformed)$fatal(1,"batch data lost");
  $display("TB_PASS batched quaternion and linear reports honor readiness without loss");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
