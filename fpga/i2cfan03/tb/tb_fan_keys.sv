`timescale 1ns/1ps
module tb_fan_keys;
 reg clk=0;always #5 clk=!clk;
 reg rst_n=0,key0_n=1,key1_n=1,key2_n=1,demo_mode=1,layout_chord_free=1;
 reg [3:0]note_count=12;
 wire action_press,expression_hold,sensor_reset,layout_cycle,layout_ready;wire [3:0]demo_zone;
 integer actions=0,cycles=0;
 instrument_keys #(.CLK_HZ(1000),.DEBOUNCE_TICKS(3),.ALLOW_TEST(0),.ALLOW_MENU(0),.ALLOW_LAYOUT(1),.LAYOUT_HOLD_TICKS(20)) dut(.clk(clk),.rst_n(rst_n),.key0_n(key0_n),.key1_n(key1_n),.key2_n(key2_n),.demo_mode(demo_mode),.layout_chord_free(layout_chord_free),.note_count(note_count),.action_press(action_press),.expression_hold(expression_hold),.sensor_reset(sensor_reset),.layout_cycle(layout_cycle),.layout_ready(layout_ready),.demo_zone(demo_zone));
 always @(negedge clk)begin if(action_press)actions++;if(layout_cycle)cycles++;end
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 task short0;begin key0_n=0;tick(10);key0_n=1;tick(10);end endtask
 initial begin tick(4);rst_n=1;tick(4);short0();if(actions!=1 || cycles)$fatal(1,"short action lost");
 key0_n=0;tick(30);if(!layout_ready || cycles || actions!=1)$fatal(1,"long changed early");tick(30);key0_n=1;tick(10);
 if(cycles!=1 || actions!=1 || layout_ready)$fatal(1,"release cycle leaked short action");
 short0();if(actions!=2 || cycles!=1)$fatal(1,"next short blocked");
 key0_n=0;tick(12);layout_chord_free=0;tick(20);key0_n=1;tick(10);layout_chord_free=1;
 if(actions!=2 || cycles!=1)$fatal(1,"three-key chord produced layout/calibration");
 key0_n=0;tick(30);demo_mode=0;tick(3);key0_n=1;tick(10);if(actions!=2 || cycles!=1)$fatal(1,"mode transition held action");
 demo_mode=1;tick(4);
 repeat(14)begin key2_n=0;tick(10);key2_n=1;tick(10);end
 if(demo_zone!=11)$fatal(1,"demo cannot reach 12th or wraps");
 note_count=5;tick(4);if(demo_zone!=2)$fatal(1,"layout clamp failed");
 repeat(8)begin key1_n=0;tick(10);key1_n=1;tick(10);end
 if(demo_zone!=0)$fatal(1,"left endpoint wraps");
 $display("TB_PASS KEY0 short action / long release layout, no repeat, chord cancellation, mode transition, 12-note demo bounds");$finish;
 end
 initial begin #100000;$fatal(1,"keys watchdog");end
endmodule
