`timescale 1ns/1ps
module tb_ui21_encoder;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,encoder_a=1,encoder_b=1,encoder_button_n=1;
 wire encoder_step,encoder_direction,encoder_short,encoder_long,pedal_toggle;wire[1:0]wrist_short,wrist_long;wire[3:0]button_ready;wire[15:0]invalid_transitions;
 performance_controls #(.CLK_HZ(1000),.ENC_DEBOUNCE_MS(2),.BUTTON_DEBOUNCE_MS(2),.SHORT_MS(4),.LONG_MS(20)) dut(.clk(clk),.rst_n(rst_n),.enabled(1'b1),.encoder_a(encoder_a),.encoder_b(encoder_b),.encoder_button_n(encoder_button_n),.pedal_n(1'b1),.wrist_button_n(2'b11),.*);
 integer positive=0,negative=0,shorts=0,longs=0;
 always @(posedge clk)begin if(encoder_step)begin if(encoder_direction)positive++;else negative++;end if(encoder_short)shorts++;if(encoder_long)longs++;end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task phase(input[1:0]p);begin {encoder_a,encoder_b}=p;cycles(7);end endtask
 initial begin
  cycles(3);rst_n=1;cycles(12);
  phase(2);phase(0);phase(1);phase(3);cycles(2);if(positive!=1 || negative!=0)$fatal(1,"positive detent");
  phase(1);phase(0);phase(2);phase(3);cycles(2);if(negative!=1)$fatal(1,"negative detent");
  phase(0);if(invalid_transitions==0)$fatal(1,"invalid transition not counted");phase(3);
  encoder_button_n=0;cycles(30);encoder_button_n=1;cycles(12);
  if(longs!=1 || shorts!=0)$fatal(1,"long release leaked short");
  encoder_button_n=0;cycles(12);encoder_button_n=1;cycles(12);
  if(shorts!=1 || longs!=1)$fatal(1,"short release");
  $display("TB_PASS raw EC11 quadrature direction/illegal transition/short-long exclusivity");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
