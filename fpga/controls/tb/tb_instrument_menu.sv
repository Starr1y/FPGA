`timescale 1ns/1ps
module tb_instrument_menu;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,enabled=1;
 reg encoder_step=0,encoder_direction=0,encoder_short=0,encoder_long=0,pedal_toggle=0;
 reg[1:0]wrist_short=0,wrist_long=0,imu_enabled=3;
 wire focus,editing,visible,chord_mode,muted;wire[3:0]page,presets,release_ids,profiles;
 wire[1:0]effect_mode,calibrate;wire[7:0]effect_wet,chorus_depth,feedback;wire[13:0]delay_samples;
 instrument_menu dut(.*);
 task step(input bit up);begin @(negedge clk);encoder_direction=up;encoder_step=1;@(negedge clk);encoder_step=0;end endtask
 task click;begin @(negedge clk);encoder_short=1;@(negedge clk);encoder_short=0;end endtask
 task back;begin @(negedge clk);encoder_long=1;@(negedge clk);encoder_long=0;end endtask
 task item(input integer target);begin if(editing)click();while(page!=target)step(1);click();end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  if(!muted || effect_mode!=0 || release_ids!=5 || focus || editing || visible)$fatal(1,"menu defaults");
  step(0);if(page!=10 || editing || profiles!=0 || !visible)$fatal(1,"menu wrap must open without changing values");
  item(1);step(1);step(1);if(presets!=2)$fatal(1,"left preset edit");
  item(0);step(1);if(!focus)$fatal(1,"focus edit");
  item(1);repeat(6)step(1);if(presets!=14)$fatal(1,"preset cap/right ownership");
  item(2);repeat(5)step(1);if(release_ids!=9)$fatal(1,"release cap/ownership");
  item(10);step(1);if(profiles!=4)$fatal(1,"layout ownership");
  item(3);step(1);if(effect_mode!=1 || delay_samples!=4800 || feedback!=96)$fatal(1,"delay preset");
  item(5);step(1);if(delay_samples!=4848)$fatal(1,"1ms delay step");
  item(6);repeat(40)step(1);if(feedback!=192)$fatal(1,"echo feedback stability cap");
  item(3);step(1);if(effect_mode!=2 || delay_samples!=576 || feedback!=0)$fatal(1,"chorus own params");
  item(5);step(0);if(delay_samples!=528)$fatal(1,"chorus delay edit");
  item(6);repeat(5)step(1);if(feedback!=0)$fatal(1,"chorus feedback must remain zero");
  item(3);step(1);if(effect_mode!=3 || delay_samples!=3840 || feedback!=80)$fatal(1,"reverb own params");
  item(6);repeat(40)step(1);if(feedback!=128)$fatal(1,"reverb feedback stability cap");
  item(5);repeat(300)step(1);if(delay_samples!=16368)$fatal(1,"delay max bound");
  repeat(400)step(0);if(delay_samples!=48)$fatal(1,"delay min bound");
  item(3);step(0);if(delay_samples!=528)$fatal(1,"chorus params overwritten by reverb");
  step(0);if(delay_samples!=4848 || feedback!=192)$fatal(1,"delay params not retained");
  item(4);repeat(50)step(1);if(effect_wet!=255)$fatal(1,"wet upper saturation");
  repeat(50)step(0);if(effect_wet!=0)$fatal(1,"wet lower saturation");
  item(7);repeat(50)step(1);if(chorus_depth!=255)$fatal(1,"depth saturation");
  item(9);step(0);if(muted)$fatal(1,"mute edit");
  item(8);step(1);@(negedge clk);encoder_step=1;encoder_direction=1;pedal_toggle=1;@(negedge clk);encoder_step=0;pedal_toggle=0;
  if(chord_mode)$fatal(1,"pedal precedence");
  @(negedge clk);pedal_toggle=1;@(negedge clk);pedal_toggle=0;
  @(negedge clk);wrist_short=3;@(negedge clk);wrist_short=0;if(calibrate!=3)$fatal(1,"wrist origin ownership");
  @(negedge clk);if(calibrate!=0)$fatal(1,"origin pulse length");imu_enabled=1;wrist_short=3;
  @(negedge clk);wrist_short=0;if(calibrate!=1)$fatal(1,"unenabled origin");
  @(negedge clk);wrist_long=1;@(negedge clk);wrist_long=0;if(profiles!=5)$fatal(1,"wrist independent layout");
  @(negedge clk);encoder_step=1;encoder_short=1;encoder_direction=0;@(negedge clk);encoder_step=0;encoder_short=0;
  if(editing || !chord_mode)$fatal(1,"click wins over simultaneous rotation");
  back();if(page!=0 || visible)$fatal(1,"back closes menu");click();if(!visible || editing)$fatal(1,"first click must open, not edit");enabled=0;
  @(negedge clk);wrist_short=3;pedal_toggle=1;encoder_step=1;@(negedge clk);wrist_short=0;pedal_toggle=0;encoder_step=0;
  if(editing || calibrate || !chord_mode)$fatal(1,"disabled events modified settings");
  $display("TB_PASS menu navigation/editing and ownership; per-mode delay/feedback retention, saturated bounds, mute/pedal priority, wrist origins/layout, disabled event discard");$finish;
 end
 initial begin #200000;$fatal(1,"menu watchdog");end
endmodule
