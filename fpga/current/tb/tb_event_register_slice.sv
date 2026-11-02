`timescale 1ns/1ps
module tb_event_register_slice;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,flush=0,in_valid=0,out_ready=0;reg[1:0]cancel=0;
 reg[63:0]epochs={32'd9,32'd7},in_data=0;wire in_ready,out_valid;wire[63:0]out_data;
 event_register_slice dut(.*);
 task tick;@(posedge clk);#1;endtask
 task input_event(input hand,input[7:0]id);
 begin @(negedge clk);if(!in_ready)$fatal(1,"test producer not ready");
 in_data=0;in_data[63:32]=hand ? epochs[63:32] : epochs[31:0];
 in_data[29]=hand;in_data[11:4]=id;in_data[20:14]=80;in_valid=1;tick();
 @(negedge clk);in_valid=0;end endtask
 reg[63:0]held;
 initial begin
  tick();rst_n=1;tick();if(!in_ready || out_valid)$fatal(1,"empty state");
  input_event(0,7);held=out_data;
  if(!out_valid || out_data!==in_data || in_ready)$fatal(1,"registered event metadata");
  repeat(3)begin tick();if(!out_valid || out_data!==held)$fatal(1,"backpressure changed event");end
  @(negedge clk);out_ready=1;#1;if(in_ready)$fatal(1,"combinational downstream ready bypassed register");
  tick();if(out_valid || !in_ready)$fatal(1,"event not consumed exactly once");
  @(negedge clk);out_ready=0;
  input_event(1,8);cancel=1;#1;if(!out_valid)$fatal(1,"hand0 cancellation dropped hand1");
  cancel=2;#1;if(out_valid)$fatal(1,"hand1 cancel did not immediately suppress output");
  tick();cancel=0;tick();if(out_valid || !in_ready)$fatal(1,"canceled slot retained");
  input_event(0,9);epochs[31:0]=8;#1;if(out_valid)$fatal(1,"stale epoch escaped");tick();
  input_event(0,10);flush=1;#1;if(out_valid || in_ready)$fatal(1,"source/STOP flush not immediate");
  tick();@(negedge clk);flush=0;tick();if(out_valid || !in_ready)$fatal(1,"flush replay");
  input_event(1,11);out_ready=1;tick();tick();if(out_valid)$fatal(1,"duplicate event");
  $display("TB_PASS event register: stable backpressure, isolated ready, paired payload, hand-specific cancel, epochs, STOP/source flush, no duplicates");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
