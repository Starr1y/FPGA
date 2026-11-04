`timescale 1ns/1ps
module tb_lite_chord;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,ev=0;wire ready;reg[63:0]data=0;
 reg[127:0]env=0;wire legato_taken;reg[1:0]pressed=0;reg[31:0]bend=0;wire[7:0]owned,gates,hold;
 wire cfg;wire[127:0]cfgdata;wire[55:0]notes;wire[63:0]bright;wire[31:0]invalid,stolen;
 dual_voice_scheduler #(.VOICES(8)) d(.clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready),.event_data(data),
 .release_pending(2'b0),.epochs(64'b0),.chord_mode(1'b1),.preset_ids(6'b0),.release_ids(4'b0),.hold_ticks_left(0),.hold_ticks_right(0),
 .mono_glide(2'b0),.bend_cents(0),.vibrato_cents(0),.brightness(16'h8080),.legato_enable(pressed),.legato_taken(legato_taken),.envelopes(env),.release_due(8'b0),
 .config_valid(cfg),.config_data(cfgdata),.config_ready(1'b1),.voice_brightness(bright),.owned(owned),.gates(gates),.notes(notes),
 .invalid_events(invalid),.stolen_notes(stolen),.wrist_enabled(2'b11),.wrist_pressed(pressed),.wrist_bend(bend),.wrist_hold(hold));
 task note(input[3:0]z,input[7:0]id);begin
  @(negedge clk);while(!ready)@(negedge clk);data={32'b0,2'b0,1'b0,z,2'b0,2'b0,7'd60,2'b0,id,4'b0};ev=1;
  @(negedge clk);ev=0;repeat(200)@(negedge clk);
 end endtask
 reg[31:0]last_freq[0:7];integer i;
 always @(posedge clk)if(cfg)begin last_freq[cfgdata[2:0]]<=cfgdata[39:8];end
 integer triggers=0,slides=0;
 always @(posedge clk)begin if(cfg && cfgdata[58])triggers<=triggers+1;if(legato_taken)slides<=slides+1;end
 initial begin
  #30;rst_n=1;note(0,1);env={64'b0,{4{16'd32768}}};pressed=1;bend=1200;repeat(100)@(negedge clk);
  if(last_freq[0]!==d.ftw[0]*2)$fatal(1,"bend ratio");
  note(3,2);note(4,3);
  if($countones(owned)!=3 || triggers!=3 || slides!=2)$fatal(1,"legato allocated/retriggered owned%h triggers%d slides%d",owned,triggers,slides);
  pressed=0;repeat(100)@(negedge clk);if(!gates[0] || last_freq[0]!==d.ftw[0]*2)$fatal(1,"release pitch/timer");
  env=0;note(2,4);if(triggers!=6)$fatal(1,"new strike missing");
  $display("TB_PASS chord live group legato/no allocation/no retrigger/release gate retained/new onset");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
