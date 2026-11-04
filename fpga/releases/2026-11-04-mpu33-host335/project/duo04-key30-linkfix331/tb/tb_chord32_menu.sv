`timescale 1ns/1ps
module tb_chord32_menu;
reg clk=0;always #5 clk=~clk;reg rst_n=0,remote_valid=0;reg[3:0]remote_action=0;reg[15:0]current_value=0;reg teaching=0;
wire[5:0]field;wire[2:0]level,group_id;wire[3:0]item;wire write;wire[15:0]value;
duo04_menu d(.clk(clk),.rst_n(rst_n),.step(1'b0),.direction(1'b0),.short_press(1'b0),.long_press(1'b0),.keys(12'b0),
.remote_valid(remote_valid),.remote_action(remote_action),.running(1'b0),.mode(2'b0),.teaching_active(teaching),.finished(1'b0),.profiles(4'b0),.presets(6'b0),.volume(9'd8),.current_value(current_value),.field(field),.level(level),.group_id(group_id),.item(item),.write(write),.value(value));
duo04_panel p(.clk(clk),.rst_n(rst_n),.status(1088'b0),.status_update(1'b0));
task action(input[3:0]a);begin @(negedge clk);remote_action=a;remote_valid=1;@(negedge clk);remote_valid=0;end endtask
integer g,i;initial begin
 repeat(4)@(negedge clk);rst_n=1;
 for(g=0;g<6;g=g+1)begin
  if(d.count(g)!==p.count(g))$fatal(1,"menu count mismatch");
  for(i=0;i<d.count(g);i=i+1)if(d.field_at(g,i)!==p.field_at(g,i))$fatal(1,"display/control mapping mismatch");
 end
 action(8);if(level!=3 || group_id!=0 || field!=1)$fatal(1,"left settings");
 action(1);if(field!=7 || item!=1)$fatal(1,"left chord item missing");
 action(2);if(level!=4)$fatal(1,"edit entry");action(1);@(negedge clk);if(!write || value!=1)$fatal(1,"enable chord");
 current_value=1;action(0);@(negedge clk);if(!write || value!=0)$fatal(1,"disable chord");
 teaching=1;action(1);@(negedge clk);if(write)$fatal(1,"teaching permits chord edit");
 $display("TB_PASS HDMI/control shared menu,left chord second item,encoder toggle,teaching lock");$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
