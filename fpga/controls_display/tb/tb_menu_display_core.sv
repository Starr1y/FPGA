`timescale 1ns/1ps
// Production 50/25MHz clocks with a nonaligned phase, real pin debouncers.
module tb_menu_display_core;
 reg core_clk=0,pixel_clk=0;always #10 core_clk=~core_clk;
 initial begin #13;forever #20 pixel_clk=~pixel_clk;end
 reg core_rst_n=0,pixel_rst_n=0,controls_enabled=1;
 reg encoder_a=1,encoder_b=1,encoder_button_n=1,pedal_n=1;reg[1:0]wrist_button_n=3,imu_enabled=3;
 wire focus,editing,visible,chord_mode,muted,visible_pixel;wire[3:0]page,presets,release_ids,profiles,button_ready;
 wire[1:0]effect_mode,calibrate;wire[7:0]effect_wet,chorus_depth,feedback,red,green,blue;
 wire[13:0]delay_samples;wire[15:0]invalid_transitions;wire hsync,vsync,de;
 menu_display_core dut(.*);string folder,path;integer file,pixels;
 task milliseconds(input integer n);repeat(n*50000)@(negedge core_clk);endtask
 task phase(input[1:0]p);begin @(negedge core_clk);{encoder_a,encoder_b}=p;milliseconds(3);end endtask
 task clockwise;begin phase(2);phase(0);phase(1);phase(3);end endtask
 task click;begin @(negedge core_clk);encoder_button_n=0;milliseconds(70);encoder_button_n=1;milliseconds(25);end endtask
 task capture(input integer name);
 begin
  @(posedge dut.pixel_status_valid);@(posedge pixel_clk);@(negedge pixel_clk);#1;
  if(dut.panel.ui!==dut.pixel_status || visible_pixel!==visible)$fatal(1,"parameter packing / frame visibility mismatch");
  if(dut.pixel_status!==dut.core_status)$fatal(1,"stable controls did not reach pixel snapshot");
  wait(dut.panel.x==0 && dut.panel.y==0);@(negedge pixel_clk);#1;
  path=$sformatf("%s/linked-%0d.ppm",folder,name);file=$fopen(path,"wb");if(!file)$fatal(1,"linked menu path");
  $fwrite(file,"P6\n640 480\n255\n");pixels=0;
  while(pixels<640*480)begin
   if(de)begin $fwrite(file,"%c%c%c",red,green,blue);pixels++;end
   @(negedge pixel_clk);#1;
  end
  $fclose(file);
 end endtask
 always @(negedge pixel_clk)if(pixel_rst_n && dut.pixel_status_valid)begin
  if(dut.panel.y<480)$fatal(1,"menu snapshot changed during active scan");
 end
 initial begin
  if(!$value$plusargs("OUT=%s",folder))folder=".";
  repeat(6)@(negedge core_clk);core_rst_n=1;pixel_rst_n=1;milliseconds(25);
  if(visible || !muted || button_ready!=15)$fatal(1,"linked reset defaults");capture(0);
  clockwise();if(!visible || editing || page!=1)$fatal(1,"actual quadrature did not open timbre item");capture(1);
  click();if(!editing)$fatal(1,"actual rotary press did not enter editing");clockwise();
  if(presets!=1 || focus)$fatal(1,"actual rotary edit changed wrong hand");capture(2);
  controls_enabled=0;milliseconds(1);capture(3);
  if(visible_pixel || visible || editing || presets!=1 || invalid_transitions)$fatal(1,"disable did not hide/retain values");
  $display("TB_PASS real 50/25MHz control-to-menu path: raw quadrature/buttons, stable frame CDC, left bass edit, synchronized visibility, active-scan invariance, disable/retain; four RTL frames");$finish;
 end
 initial begin #400000000;$fatal(1,"linked menu watchdog");end
endmodule
