`timescale 1ns/1ps
module tb_wrist_group;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,ev=0;wire ready;reg[63:0]data=0;
 reg chord=1;reg[1:0]pressed=0;reg[31:0]bend=0;wire[7:0]owned,gates,hold;
 wire cfg;wire[127:0]cfgdata;wire[55:0]notes;wire[63:0]bright;wire[31:0]invalid,stolen;
 dual_voice_scheduler #(.VOICES(8)) d(.clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready),.event_data(data),
 .release_pending(2'b0),.epochs(64'b0),.chord_mode(chord),.preset_ids(6'b0),.release_ids(4'b0),.hold_ticks_left(0),.hold_ticks_right(0),
 .mono_glide(2'b0),.bend_cents(0),.vibrato_cents(0),.brightness(16'h8080),.envelopes(128'b0),.release_due(8'b0),
 .config_valid(cfg),.config_data(cfgdata),.config_ready(1'b1),.voice_brightness(bright),.owned(owned),.gates(gates),.notes(notes),
 .invalid_events(invalid),.stolen_notes(stolen),.wrist_enabled(2'b11),.wrist_pressed(pressed),.wrist_bend(bend),.wrist_hold(hold));
 task note(input[3:0]z,input[7:0]id);begin
  @(negedge clk);while(!ready)@(negedge clk);data={32'b0,2'b0,1'b0,z,2'b0,2'b0,7'd60,2'b0,id,4'b0};ev=1;
  @(negedge clk);ev=0;repeat(200)@(negedge clk);
 end endtask
 reg[31:0]last_freq[0:7];integer i;
 always @(posedge clk)if(cfg)begin last_freq[cfgdata[2:0]]<=cfgdata[39:8];end
 initial begin
  #30;rst_n=1;note(0,1);pressed=1;bend=1200;repeat(300)@(negedge clk);
  if($countones(hold)!=3)$fatal(1,"chord ownership");
  note(1,255);bend=600;repeat(300)@(negedge clk);
  if($countones(hold)!=3)$fatal(1,"steal transfer");
  note(2,1);bend=1200;repeat(300)@(negedge clk);
  if($countones(hold)!=3 || d.latest_group[2])$fatal(1,"id wrap captured old tail");
  for(i=0;i<4;i=i+1)if(hold[i] && last_freq[i]!==d.ftw[i]*2)$fatal(1,"chord interval changed");
  pressed=0;repeat(300)@(negedge clk);if(gates)$fatal(1,"chord release");
  $display("TB_PASS chord shared bend, stealing and event id wrap isolation");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
