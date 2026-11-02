`timescale 1ns/1ps
module cdc_phase_case #(parameter PHASE=0)(output reg done=0);
 reg core=0,pixel=0,rst=0;always #10 core=~core;
 initial begin #(PHASE*0.5);forever #10.204 pixel=~pixel;end
 reg[31:0]count=0;always @(negedge core)count=count+1;
 wire[1087:0]source={34{count}};wire[1087:0]received;wire valid;
 reg request=0;
 video_status_cdc #(.WIDTH(1088))dut(core,rst,source,pixel,rst,request,received,valid);
 realtime source_time=0,min_margin=1000000;reg[1087:0]expected;integer snapshots=0,captures=0;
 always @(dut.held_status)if(rst)begin source_time=$realtime;expected=dut.held_status;snapshots=snapshots+1;end
 always @(posedge pixel)begin #0.001;if(rst && valid)begin
  if(received!==expected)$fatal(1,"phase%0d torn/stale snapshot",PHASE);
  if(captures>=snapshots)$fatal(1,"phase%0d duplicate/spurious capture",PHASE);
  if($realtime-source_time<61.222)$fatal(1,"phase%0d insufficient source-settle interval %0f",PHASE,$realtime-source_time);
  if($realtime-source_time<min_margin)min_margin=$realtime-source_time;
  captures=captures+1;
  if(captures==1000)begin done=1;$display("PHASE %0d snapshots=%0d captures=%0d minimum_settle_ns=%0f",PHASE,snapshots,captures,min_margin);end
 end end
 initial begin #201;rst=1;request=1;end
endmodule
module tb_video70h_cdc;
 wire[40:0]done;
 generate for(genvar i=0;i<=40;i=i+1)begin:g cdc_phase_case #(.PHASE(i))c(done[i]);end endgenerate
 initial begin wait(&done);$display("TB_PASS 41 initial phases0..20ns,1000captures each,1088bit snapshots, continuous requests under backpressure, min source-to-capture >=3pixel periods");$finish;end
 initial begin #1000000;$fatal(1,"CDC timeout");end
endmodule
