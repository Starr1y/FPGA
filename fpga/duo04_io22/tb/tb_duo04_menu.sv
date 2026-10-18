// BASELINE 2.0 ONLY. Use tb_ui21_controls / tb_ui21_lesson for 2.1 interfaces.
`timescale 1ns/1ps
module tb_duo04_menu;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,step=0,direction=0,short_press=0,long_press=0,running=0;
 reg[15:0]current_value=0;wire[1:0]page;wire[4:0]field;wire editing,write;wire[15:0]value;
 duo04_menu dut(.*);
 task turn(input bit d);begin @(negedge clk);direction=d;step=1;@(negedge clk);step=0;end endtask
 task press;begin @(negedge clk);short_press=1;@(negedge clk);short_press=0;end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;press();
  if(!write || field!=22 || value!=1)$fatal(1,"main start");
  turn(1);if(page!=1 || field!=0)$fatal(1,"settings entry");
  press();if(!editing)$fatal(1,"edit entry");
  current_value=2;turn(1);if(value!=2 || !write)$fatal(1,"mode saturation");
  current_value=0;turn(0);if(value!=0)$fatal(1,"lower saturation");
  press();repeat(19)turn(1);turn(1);if(page!=2)$fatal(1,"lesson page");
  press();if(!write || field!=20)$fatal(1,"lesson restart semantic write");
  turn(1);if(page!=3)$fatal(1,"status page");
  press();if(!write || field!=21)$fatal(1,"calibration");
  @(negedge clk);long_press=1;@(negedge clk);long_press=0;
  if(page!=0 || editing)$fatal(1,"long return");
  $display("TB_PASS menu navigation/edit/saturation/start/lesson/calibration/return");$finish;
 end
endmodule
