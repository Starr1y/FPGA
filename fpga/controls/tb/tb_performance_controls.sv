`timescale 1ns/1ps
module tb_performance_controls #(parameter EDGES=4);
 reg clk=0;always #5 clk=~clk;reg rst_n=0,enabled=0;
 reg encoder_a=1,encoder_b=1,encoder_button_n=1,pedal_n=0;reg[1:0]wrist_button_n=3;
 wire encoder_step,encoder_direction,encoder_short,encoder_long,pedal_toggle;wire[1:0]wrist_short,wrist_long;
 wire[3:0]button_ready;wire[15:0]invalid_transitions;
 performance_controls #(.CLK_HZ(1000),.ENC_DEBOUNCE_MS(2),.EDGES_PER_STEP(EDGES),.BUTTON_DEBOUNCE_MS(3),.SHORT_MS(5),.LONG_MS(20)) dut(.*);
 wire focus,editing,visible,chord_mode,muted;wire[3:0]page,presets,release_ids,profiles;
 wire[1:0]effect_mode,calibrate;wire[7:0]effect_wet,chorus_depth,feedback;wire[13:0]delay_samples;
 instrument_menu menu(.clk(clk),.rst_n(rst_n),.enabled(enabled),.encoder_step(encoder_step),.encoder_direction(encoder_direction),
  .encoder_short(encoder_short),.encoder_long(encoder_long),.pedal_toggle(pedal_toggle),.wrist_short(wrist_short),.wrist_long(wrist_long),
  .imu_enabled(2'b11),.focus(focus),.editing(editing),.visible(visible),.page(page),.presets(presets),.release_ids(release_ids),.profiles(profiles),
  .chord_mode(chord_mode),.muted(muted),.effect_mode(effect_mode),.calibrate(calibrate),.effect_wet(effect_wet),.chorus_depth(chorus_depth),.delay_samples(delay_samples),.feedback(feedback));
 integer up=0,down=0,pedals=0,shorts=0,longs=0,lefts=0,rights=0,leftlongs=0,rightlongs=0;
 always @(negedge clk)begin
  if(encoder_step)begin if(encoder_direction)up++;else down++;end
  if(pedal_toggle)pedals++;
  if(encoder_short)shorts++;if(encoder_long)longs++;
  if(wrist_short[0])lefts++;if(wrist_short[1])rights++;
  if(wrist_long[0])leftlongs++;if(wrist_long[1])rightlongs++;
 end
 task cycles(input integer n);repeat(n)@(posedge clk);endtask
 task phase(input[1:0]p);begin @(negedge clk);{encoder_a,encoder_b}=p;cycles(7);end endtask
 task cw;begin phase(2);phase(0);phase(1);phase(3);end endtask
 task ccw;begin phase(1);phase(0);phase(2);phase(3);end endtask
 initial begin
  cycles(5);@(negedge clk);rst_n=1;enabled=1;cycles(12);
  if(button_ready[1] || pedals)$fatal(1,"held pedal at enable created action");
  @(negedge clk);pedal_n=1;cycles(12);if(button_ready!=15)$fatal(1,"unpressed readiness");
  cw();ccw();cycles(3);if(up!=4/EDGES || down!=4/EDGES)$fatal(1,"encoder directions/detents");
  phase(2);phase(3);cycles(2);if(up!=4/EDGES || down!=4/EDGES)$fatal(1,"encoder edge bounce counted");
  @(negedge clk);{encoder_a,encoder_b}=2;cycles(1);{encoder_a,encoder_b}=3;cycles(6);
  if(up!=4/EDGES || down!=4/EDGES)$fatal(1,"short phase glitch");
  phase(0);cycles(2);if(invalid_transitions!=1)$fatal(1,"diagonal transition not recorded");
  phase(3);cycles(2);if(invalid_transitions!=2)$fatal(1,"invalid recovery");
  cw();cycles(2);if(up!=8/EDGES)$fatal(1,"partial position not reset after invalid transition");
  @(negedge clk);pedal_n=0;cycles(60);if(pedals)$fatal(1,"pedal auto-repeat");
  @(negedge clk);pedal_n=1;cycles(12);if(pedals!=1)$fatal(1,"long pedal release not one toggle");
  @(negedge clk);pedal_n=0;cycles(10);pedal_n=1;cycles(12);if(pedals!=2)$fatal(1,"short pedal");
  @(negedge clk);encoder_button_n=0;cycles(10);encoder_button_n=1;cycles(12);
  if(shorts!=1 || longs)$fatal(1,"encoder short select");
  if(!editing || page!=4/EDGES)$fatal(1,"physical encoder select not wired to menu");
  // Navigate back to Timbre for the two-edge variant, then edit through real pins.
  if(EDGES==2)begin
   @(negedge clk);encoder_button_n=0;cycles(10);encoder_button_n=1;cycles(12);phase(1);phase(0);
   @(negedge clk);encoder_button_n=0;cycles(10);encoder_button_n=1;cycles(12);
   phase(1);phase(3);phase(2);phase(0);
  end
  else cw();
  cycles(2);if(presets!=4/EDGES)$fatal(1,"real quadrature failed to edit selected hand timbre");
  @(negedge clk);encoder_button_n=0;cycles(35);encoder_button_n=1;cycles(12);
  if(shorts!=(EDGES==2 ? 3 : 1) || longs!=1 || editing)$fatal(1,"encoder long select");
  @(negedge clk);wrist_button_n=0;cycles(10);wrist_button_n=3;cycles(12);
  if(lefts!=1 || rights!=1)$fatal(1,"wrist hand isolation");
  @(negedge clk);wrist_button_n[0]=0;cycles(35);wrist_button_n[0]=1;cycles(12);
  if(leftlongs!=1 || rightlongs || profiles!=1)$fatal(1,"wrist long ownership/menu layout");
  @(negedge clk);wrist_button_n[1]=0;cycles(10);enabled=0;cycles(30);enabled=1;cycles(30);
  wrist_button_n[1]=1;cycles(12);if(rights!=1 || rightlongs)$fatal(1,"disable/held reenable leaked release");
  $display("TB_PASS physical control logic %0d edges/detent: CW/CCW, bounce/glitch, diagonal recovery, held-at-enable, single release actions and wrist ownership",EDGES);$finish;
 end
 initial begin #50000;$fatal(1,"control watchdog");end
endmodule
