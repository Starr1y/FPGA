`timescale 1ns/1ps
module tb_ui_keys;
 reg clk=0;always #5 clk=!clk;
 reg rst_n=0,key0_n=1,key1_n=1,key2_n=1;
 wire enabled,f1,f2,toggle,long_ready,action,expression_hold,sensor_reset;
 wire [2:0] demo_zone;
 integer page_changes=0,en_changes=0,actions=0,resets=0;
 reg previous_enabled=0;
 bench_manual_enable #(.CLK_HZ(1000)) dut(.clk(clk),.rst_n(rst_n),.key1_n(key1_n),.key2_n(key2_n),
  .enabled(enabled),.filtered_key1_n(f1),.filtered_key2_n(f2),.view_toggle(toggle),.long_ready(long_ready));
 instrument_keys #(.CLK_HZ(1000),.ALLOW_TEST(0),.ALLOW_MENU(0)) keys(
  .clk(clk),.rst_n(rst_n),.key0_n(key0_n),.key1_n(f1),.key2_n(f2),.demo_mode(1'b1),
  .action_press(action),.expression_hold(expression_hold),.sensor_reset(sensor_reset),.demo_zone(demo_zone));
 always @(negedge clk)if(rst_n)begin
  if(toggle)page_changes++;
  if(enabled!=previous_enabled)en_changes++;
  previous_enabled=enabled;
  if(action)actions++;
  if(sensor_reset)resets++;
 end else previous_enabled=0;
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 task both(input integer n);begin key1_n=0;key2_n=0;tick(n);end endtask
 task release_both;begin key1_n=1;key2_n=1;tick(70);end endtask
 initial begin
  // Held during startup must never arm communication or flip a page.
  key1_n=0;key2_n=0;tick(5);rst_n=1;tick(2300);release_both();
  if(enabled || page_changes || en_changes)$fatal(1,"startup chord activated");
  // Switch only after a stable release; release bounce must not count twice.
  both(220);if(page_changes || enabled)$fatal(1,"early chord action");
  key1_n=1;key2_n=1;tick(6);key1_n=0;key2_n=0;tick(5);release_both();
  if(page_changes!=1 || enabled || demo_zone!=3 || actions || resets)$fatal(1,"short chord leaked into instrument actions");
  // Accidental taps below 50 ms are discarded.
  both(40);release_both();if(page_changes!=1)$fatal(1,"bounce/tap accepted");
  // 2 s command remains one permission toggle, not a page toggle.
  both(2100);if(enabled || !long_ready)$fatal(1,"permission changed before release or missing release hint");
  key1_n=1;tick(1700);if(enabled || resets)$fatal(1,"partial release leaked reset");
  release_both();if(!enabled || long_ready || en_changes!=1 || page_changes!=1)$fatal(1,"long chord changed page or hint stuck");
  // Short page change preserves running permission.
  both(200);release_both();if(!enabled || en_changes!=1 || page_changes!=2)$fatal(1,"page action changed communication");
  // Ordinary single-key actions retain the established behavior.
  key0_n=0;tick(50);key0_n=1;tick(60);if(actions!=1)$fatal(1,"KEY0 lost calibration/demo action");
  key1_n=0;tick(1650);key1_n=1;tick(60);if(resets!=1)$fatal(1,"single KEY2 lost reset");
  both(2100);release_both();if(enabled || en_changes!=2 || page_changes!=2 || resets!=1)$fatal(1,"stop chord regression");
  $display("TB_PASS short/long chords, startup, bounce, partial release, permission and single key isolation");$finish;
 end
 initial begin #200000;$fatal(1,"key watchdog");end
endmodule
