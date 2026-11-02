`timescale 1ns/1ps
module tb_menu_edit_pipeline;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,step=0,direction=0,short_press=0,long_press=0,remote_valid=0,running=0,teaching_active=0,finished=0;
reg[11:0]keys=0;reg[3:0]remote_action=0;reg[1:0]mode=0;reg[3:0]profiles=0;reg[5:0]presets=0;reg[8:0]volume=8;reg[15:0]current_value=0;
wire[1:0]page;wire[5:0]field;wire editing,write,active_hand,stop;wire[15:0]value,serial;wire[2:0]level,group_id;wire[3:0]item;wire[7:0]notice;
reg[5:0]test_field=8;
duo04_menu dut(.*);
task edit(input integer f,c,up,expected);begin
 @(negedge clk);test_field=f;current_value=c;
 @(negedge clk);remote_action=up ? 1 : 0;remote_valid=1;
 @(negedge clk);remote_valid=0;
 if(write)$fatal(1,"edit must snapshot before write");
 @(negedge clk);if(!write || value!=expected)$fatal(1,"field %d current %d dir %d expected %d actual %d",f,c,up,expected,value);
 @(negedge clk);if(write)$fatal(1,"write repeated");
end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 force dut.level=4;force dut.field=test_field;
 edit(8,248,1,252);edit(8,252,1,256);edit(8,256,1,256);edit(8,4,0,0);edit(8,0,0,0);
 edit(10,248,1,255);edit(10,8,0,0);
 edit(11,100,0,100);edit(11,9900,1,10000);edit(12,1500,0,1400);
 edit(1,3,1,3);edit(3,2,1,2);edit(29,1,1,1);edit(29,1,0,0);
 // STOP in the arithmetic stage cancels the captured edit.
 @(negedge clk);remote_valid=1;remote_action=1;
 @(negedge clk);remote_action=11;
 @(negedge clk);remote_valid=0;if(write || !stop)$fatal(1,"STOP did not flush pending edit");
 @(negedge clk);if(write)$fatal(1,"edit replayed after STOP");
 release dut.field;release dut.level;
 $display("TB_PASS menu pipeline bounds / one write / STOP cancellation");$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
