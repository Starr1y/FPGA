`timescale 1ns/1ps
// A bend arriving after the lookup address was latched must leave the Voice
// dirty until a new configuration contains that bend, even under backpressure.
module tb_scheduler_pipeline;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,event_valid=0,config_ready=0;
 reg[63:0]event_data=0;reg[31:0]bend_cents=0;
 wire event_ready,config_valid;wire[127:0]config_data;
 wire[1:0]release_ack;wire[63:0]voice_brightness;wire[7:0]owned,gates;
 wire[55:0]notes;wire[31:0]invalid_events,stolen_notes;
 wire committed,committed_hand;wire[7:0]committed_id;
 dual_voice_scheduler #(.VOICES(8)) dut(.clk(clk),.rst_n(rst_n),
  .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
  .release_pending(2'b0),.release_ack(release_ack),.epochs(64'b0),
  .chord_mode(1'b0),.preset_ids(6'b0),.release_ids(4'b0),
  .hold_ticks_left(32'd72000),.hold_ticks_right(32'd72000),.mono_glide(2'b0),
  .bend_cents(bend_cents),.vibrato_cents(32'b0),.brightness(16'h8080),
  .envelopes(128'b0),.release_due(8'b0),.config_valid(config_valid),
  .config_data(config_data),.config_ready(config_ready),
  .voice_brightness(voice_brightness),.owned(owned),.gates(gates),.notes(notes),
  .invalid_events(invalid_events),.stolen_notes(stolen_notes),
  .committed(committed),.committed_id(committed_id),.committed_hand(committed_hand));
 reg[127:0]held;reg[48:0]expected;integer accepted=0;
 always @(posedge clk)if(rst_n && config_valid && config_ready)accepted<=accepted+1;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  event_data[28:25]=3;event_data[20:14]=80;event_data[11:4]=7;
  event_valid=1;@(negedge clk);event_valid=0;
  wait(dut.cfg_state==5);@(negedge clk);bend_cents=100;
  wait(config_valid);@(negedge clk);held=config_data;
  repeat(5)begin @(negedge clk);if(!config_valid || config_data!==held)$fatal(1,"configuration changed under backpressure");end
  config_ready=1;
  wait(accepted>=2);repeat(15)@(negedge clk);
  expected=dut.ftw[0]*dut.cent_rom[330];
  if(config_data[39:8]!==expected[47:16] || dut.dirty[0])$fatal(1,"mid-lookup bend lost: got %d expected %d dirty %b",config_data[39:8],expected[47:16],dut.dirty[0]);
  if(invalid_events || stolen_notes)$fatal(1,"unexpected allocation error");
  $display("TB_PASS scheduler lookup pipeline preserves mid-flight bend/revision and immutable backpressure");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
