`timescale 1ns/1ps
// Real board top and raw input pins -> canonical state -> full frame CDC -> RGB.
// Only key durations are shortened, sensors remain disabled. No forced state.
module tb_duo_board_video;
 reg clk=0;always #10 clk=~clk;reg reset_key=0;
 reg key0_n=1,key1_n=1,key2_n=1,encoder_a=1,encoder_b=1,encoder_button_n=1,pedal_n=1;
 reg[1:0]wrist_button_n=3;tri1[1:0]imu_scl,imu_sda,imu_rst_n;wire[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 top_duo03 dut(.*);
 defparam dut.keys.DEBOUNCE_MS=2,dut.keys.SHORT_MS=5,dut.keys.LONG_MS=20,dut.keys.COMBO_MS=30,dut.keys.EXPRESS_MS=10;
 integer file,pixels;string folder,path;
 task ms(input integer n);repeat(n*50000)@(negedge clk);endtask
 task tap(input integer key,n);
 begin case(key)0:key0_n=0;1:key1_n=0;2:key2_n=0;endcase ms(n);key0_n=1;key1_n=1;key2_n=1;ms(5);end endtask
 task phase(input[1:0]p);begin {encoder_a,encoder_b}=p;ms(3);end endtask
 task clockwise;begin phase(2);phase(0);phase(1);phase(3);end endtask
 task rotary_long;begin encoder_button_n=0;ms(28);encoder_button_n=1;ms(5);end endtask
 task capture(input integer id);
 begin
  @(posedge dut.display.pixel_status_valid);@(posedge dut.display.pixel_clk);@(negedge dut.display.pixel_clk);#1;
  if(dut.display.pixel_status!==dut.display_status)$fatal(1,"board state snapshot lost data");
  if(dut.display.panel.menu.ui[63:0]!==dut.menu_status || dut.display.panel.menu_visible!==dut.visible)$fatal(1,"control-to-renderer packing");
  wait(dut.display.panel.performance.x==0 && dut.display.panel.performance.y==0);@(negedge dut.display.pixel_clk);#1;
  path=$sformatf("%s/board-page-%0d.ppm",folder,id);file=$fopen(path,"wb");if(!file)$fatal(1,"board RGB output");
  $fwrite(file,"P6\n640 480\n255\n");pixels=0;
  while(pixels<640*480)begin
   if(dut.display.de)begin $fwrite(file,"%c%c%c",dut.display.red,dut.display.green,dut.display.blue);pixels++;end
   @(negedge dut.display.pixel_clk);#1;
  end
  $fclose(file);
 end endtask
 initial begin
  if(!$value$plusargs("OUT=%s",folder))folder=".";
  wait(dut.rst_n);ms(6);if(dut.visible || dut.enabled || !dut.muted)$fatal(1,"board defaults");capture(0);
  key0_n=0;key1_n=0;ms(16);key0_n=1;key1_n=1;ms(5);
  if(!dut.visible || dut.page || dut.editing || dut.enabled)$fatal(1,"raw board menu open");
  tap(1,9);tap(0,12);tap(1,9);
  if(dut.page!=1 || !dut.editing || dut.presets!=1 || dut.enabled)$fatal(1,"raw board preset edit");capture(1);
  clockwise();if(dut.presets!=2 || dut.menu_status[9:8]!=2)$fatal(1,"raw encoder did not share board state");capture(2);
  rotary_long();rotary_long();if(dut.visible || dut.presets!=2 || dut.editing)$fatal(1,"raw encoder close/retain");capture(3);
  key1_n=0;key2_n=0;ms(16);key1_n=1;key2_n=1;ms(5);
  if(!dut.diagnostic || dut.visible || dut.enabled || !dut.muted || !pa_en || imu_scl!==3 || imu_sda!==3 || imu_rst_n!==3)$fatal(1,"diagnostic or safety invariant");capture(4);
  if(dut.underflows || dut.invalid_controls)$fatal(1,"board control/display path errors");
  $display("TB_PASS DUO03 full top raw keys/encoder -> one parameter bank -> actual 1024-bit frame snapshot -> menu/performance/diagnostic RGB; 50/25MHz, shortened key durations, no forced state, five RTL frames, sensors remain disabled and audio muted");$finish;
 end
 initial begin #450000000;$fatal(1,"board video watchdog");end
endmodule
