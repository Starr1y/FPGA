`timescale 1ns/1ps
module tb_ui21_controls;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;
 reg[2:0]key_n=7;wire[11:0]keys;reg[11:0]seen=0;
 duo04_keys #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.SHORT_MS(4),.LONG_MS(20),.STOP_MS(8)) kd(.clk(clk),.rst_n(rst_n),.key_n(key_n),.actions(keys));
 always @(posedge clk)if(rst_n)seen<=seen|keys;
 reg step=0,direction=1,short_press=0,long_press=0,remote_valid=0,running=0;reg[3:0]remote_action=0;
 reg[1:0]mode=0;reg teaching_active=0,finished=0;reg[3:0]profiles=0;reg[5:0]presets=0;reg[8:0]volume=8;reg[15:0]current_value=0;
 wire[1:0]page;wire[5:0]field;wire editing,write,active_hand,stop;wire[15:0]value,serial;wire[2:0]level,group_id;wire[3:0]item;wire[7:0]notice;
 duo04_menu menu(.clk(clk),.rst_n(rst_n),.step(step),.direction(direction),.short_press(short_press),.long_press(long_press),.keys(keys),.remote_valid(remote_valid),.remote_action(remote_action),.running(running),.mode(mode),.teaching_active(teaching_active),.finished(finished),.profiles(profiles),.presets(presets),.volume(volume),.current_value(current_value),.page(page),.field(field),.editing(editing),.write(write),.value(value),.active_hand(active_hand),.level(level),.group_id(group_id),.item(item),.stop(stop),.notice(notice),.serial(serial));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task action(input[3:0]a);begin @(negedge clk);remote_action=a;remote_valid=1;@(negedge clk);remote_valid=0;end endtask
 task clear_seen;begin @(negedge clk);seen=0;end endtask
 initial begin
  key_n=6;cycles(5);rst_n=1;cycles(40);key_n=7;cycles(15);
  if(seen!=0)$fatal(1,"held at reset emitted action");
  clear_seen();key_n=6;cycles(1);key_n=7;cycles(7);if(seen!=0)$fatal(1,"bounce emitted action");
  key_n=6;cycles(12);key_n=7;cycles(8);if(seen!=12'h010)$fatal(1,"K0 short %h",seen);
  clear_seen();key_n=3;cycles(30);key_n=7;cycles(8);if(seen!=12'h100)$fatal(1,"K2 long %h",seen);
  clear_seen();key_n=6;cycles(4);key_n=4;cycles(10);key_n=5;cycles(3);key_n=7;cycles(8);
  if(seen!=12'h200)$fatal(1,"menu combo leaked singles %h",seen);
  clear_seen();key_n=2;cycles(14);if(!seen[11])$fatal(1,"STOP not immediate while held");key_n=7;cycles(8);if(seen!=12'h800)$fatal(1,"STOP leaked singles");
  // Return from the menu opened by earlier keys, then exercise remote parity.
  action(3);action(3);action(7);if(!active_hand)$fatal(1,"hand not switched");
  action(6);if(!write || field!=2 || value!=1)$fatal(1,"timbre semantic edit");
  action(1);if(!write || field!=8 || value!=12)$fatal(1,"volume detent");
  action(2);if(level!=1)$fatal(1,"first encoder click should open only");
  action(2);if(!write || field!=22 || value!=1 || level!=0)$fatal(1,"second click should start");
  action(8);if(level!=3 || group_id!=1 || field!=2)$fatal(1,"current-hand settings");
  action(4);if(!editing)$fatal(1,"key confirm edit");current_value=3;action(1);cycles(1);if(!write || value!=3)$fatal(1,"upper bound");
  action(3);if(level!=3)$fatal(1,"back edit");action(3);if(level!=2)$fatal(1,"back group");action(3);
  teaching_active=1;mode=2;action(5);if(write || notice!=3)$fatal(1,"lesson layout lock");
  finished=1;running=0;action(2);action(2);if(!write || field!=27 || value!=4)$fatal(1,"finished lesson not restartable offline");
  action(11);if(!stop || write)$fatal(1,"STOP priority");
  $display("TB_PASS UI keys debounce/reset/chords/menu/encoder/context/bounds/STOP");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
