`timescale 1ns/1ps
// End-to-end pin peers -> native SHTP -> pose/negative-Z -> actual Voice engine.
// Time-scaled 1MHz clock / 2kHz render enables; separate 50MHz/48kHz test covers audio capacity.
module tb_dual_sensor_audio;
 reg clk=0;always #500 clk=~clk;reg rst_n=0;reg[1:0]enabled=0,force_reset=0,calibrate=0;
 tri1[1:0]scl,sda,sensor_reset;wire[1:0]scl_low,sda_low,reset_low,int_n,configured,online;
 wire[511:0]status;wire[63:0]drops,processing;wire[79:0]samples;wire sample_valid;wire[31:0]underflows,invalid_events;
 wire[31:0]gates;wire[223:0]notes;wire[511:0]envelopes;integer divider=0;reg sample_tick=0;
 always @(posedge clk)begin if(!rst_n)begin divider<=0;sample_tick<=0;end
  else begin sample_tick<=divider==499;divider<=divider==499 ? 0 : divider+1;end end
 for(genvar h=0;h<2;h++)begin
  assign scl[h]=scl_low[h] ? 0 : 1'bz;assign sda[h]=sda_low[h] ? 0 : 1'bz;assign sensor_reset[h]=reset_low[h] ? 0 : 1'bz;
 end
 two_hand_instrument_core #(.CLK_HZ(1000000),.HALF_DIV(2),.RESET_TICKS(1000),.BOOT_TICKS(1000),.RESET_SETUP_TICKS(1000),.HOLD_TICKS(400000)) dut(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.enabled(enabled),.force_reset(force_reset),.calibrate(calibrate),.express(2'b0),.mirror(2'b0),
  .layout_profile(4'b1000),.scl_in(scl),.sda_in(sda),.int_n(int_n),.scl_low(scl_low),.sda_low(sda_low),.reset_low(reset_low),.online(online),
  .chord_mode(1'b1),.preset_ids(4'b1000),.release_ids(4'b0),.status(status),.event_drops(drops),.processing_overruns(processing),
  .samples(samples),.sample_valid(sample_valid),.underflows(underflows),.invalid_events(invalid_events),.gates(gates),.notes(notes),.envelopes(envelopes),.monitor_voice(5'b0));
 bno_two_hand_peer lp(.sensor_rst_n(sensor_reset[0]),.scl(scl[0]),.sda(sda[0]),.int_n(int_n[0]),.configured(configured[0]));
 bno_two_hand_peer rp(.sensor_rst_n(sensor_reset[1]),.scl(scl[1]),.sda(sda[1]),.int_n(int_n[1]),.configured(configured[1]));
 task left(input integer angle,down);
  integer z,w;begin z=$rtoi(16384*$sin(angle*3.141592653589793/360));w=$rtoi(16384*$cos(angle*3.141592653589793/360));lp.sensor_report(0,0,z,w,2510-down,0);end
 endtask
 task right(input integer angle,down);
  integer z,w;begin z=$rtoi(16384*$sin(angle*3.141592653589793/360));w=$rtoi(16384*$cos(angle*3.141592653589793/360));rp.sensor_report(0,0,z,w,2510-down,0);end
 endtask
 task pair(input integer la,ra,ld,rd);
  realtime t;begin t=$realtime;fork left(la,ld);right(ra,rd);join
   if($realtime-t>=10000000)$fatal(1,"100Hz fixture overloaded");#(10000000-($realtime-t));end
 endtask
 integer audible=0;
 always @(posedge clk)if(sample_valid && samples[79:64]!=0)audible++;
 reg[31:0]right_frequency;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;enabled=3;wait(configured==3);pair(0,0,0,0);
  @(negedge clk);calibrate=3;@(negedge clk);calibrate=0;repeat(55)pair(0,0,0,0);
  if(!status[1] || !status[257])$fatal(1,"native origins failed");
  for(integer n=1;n<=7;n++)pair(0,n*10,0,0);repeat(5)pair(0,70,0,0);
  pair(0,70,256,1024);repeat(8)pair(0,70,0,0);
  if(notes[6:0]!=65 || notes[13:7]!=69 || notes[20:14]!=72 || notes[16*7+:7]!=70)
   $fatal(1,"native sensor to triad/melody mapping failed %0d/%0d/%0d R%0d",notes[6:0],notes[13:7],notes[20:14],notes[16*7+:7]);
  if(!gates[0] || !gates[1] || !gates[2] || !gates[16] || audible==0 || envelopes==0)$fatal(1,"native actual audio not active");
  right_frequency=dut.synth.audio.freq[16];
  @(negedge clk);enabled[0]=0;
  repeat(5)begin realtime t;t=$realtime;right(70,0);#(10000000-($realtime-t));end
  if(gates[15:0]!=0 || dut.synth.audio.gate[0] || !gates[16] || dut.synth.audio.freq[16]!=right_frequency || !online[1])$fatal(1,"native disable crossed audio ownership");
  if(drops || processing || underflows || invalid_events)$fatal(1,"native audio path overflow/invalid/underrun");
  $display("TB_PASS native two I2C peers -> actual reports/pose/negative-Z -> left triad/right zone10 -> real ADSR/PCM; left disable releases only left audio; scaled 1MHz/2kHz simulation, no physical audio");$finish;
 end
 initial begin #2000000000;$fatal(1,"native audio watchdog");end
endmodule
