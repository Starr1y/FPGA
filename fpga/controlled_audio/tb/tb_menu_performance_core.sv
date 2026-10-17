`timescale 1ns/1ps
// Menu semantic events -> actual 32 Voice scheduler/synth -> configurable FX
// -> actual PT8211. Sensor packets and mechanical timing are separate benches.
module tb_menu_performance_core;
 localparam VOICES=32,BANK=16;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,controls_enabled=1;reg[1:0]imu_enabled=3;
 reg encoder_step=0,encoder_direction=0,encoder_short=0,encoder_long=0,pedal_toggle=0;
 reg[1:0]wrist_short=0,wrist_long=0,push_valid=0,cancel=0;
 reg[63:0]payload=0;reg[31:0]bend_cents=0,vibrato_cents=0;reg[15:0]brightness=16'h8080;
 wire[1:0]accepted,calibrate;wire[3:0]profiles;
 wire[63:0]control_status,epochs,event_drops,cancelled_events;
 wire[31:0]owned,gates,active_voices;wire[223:0]notes;wire[511:0]envelopes,voice_samples;
 wire signed[15:0]pcm_left,pcm_right;wire pcm_valid,bck,ws,dout,amplifier_off;
 wire[31:0]underflows,invalid_events,stolen_notes,stereo_clips,fx_drops,fx_clips;
 wire[15:0]max_render_cycles;wire[1:0]active_effect;
 wire[7:0]actual_wet,active_feedback,active_depth;wire[13:0]active_delay;wire transitioning;wire[8:0]master_gain;
 // The sensor-side queue is external, as it is in two_hand_i2c_core. This bench
 // injects gesture payloads instead of simulating an additional pair of IMUs.
 wire event_valid,event_ready;wire[63:0]event_data;wire[1:0]release_pending,release_ack;
 reg[1:0]previous_enabled=0;
 always @(posedge clk)begin if(!rst_n)previous_enabled<=0;else previous_enabled<=imu_enabled;end
 wire[1:0]clear_history=cancel;
 wire[1:0]cancel_now=cancel|calibrate|(previous_enabled & ~imu_enabled);
 two_hand_event_queue sensor_queue(.clk(clk),.rst_n(rst_n),.push_valid(push_valid & imu_enabled & ~cancel_now),.push_payload(payload),
  .cancel(cancel_now),.release_ack(release_ack),.release_pending(release_pending),.epochs(epochs),
  .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),.drops(event_drops),.cancelled_events(cancelled_events),.accepted(accepted));
 menu_performance_core #(.HOLD_TICKS(25000000)) dut(.*);
 task step(input bit up);begin @(negedge clk);encoder_direction=up;encoder_step=1;@(negedge clk);encoder_step=0;@(negedge clk);end endtask
 task click;begin @(negedge clk);encoder_short=1;@(negedge clk);encoder_short=0;@(negedge clk);end endtask
 task back;begin @(negedge clk);encoder_long=1;@(negedge clk);encoder_long=0;@(negedge clk);end endtask
 task go(input integer n);begin if(control_status[4])back();while(control_status[3:0]!=n)step(1);end endtask
 task edit(input integer page,steps,input bit up);
 begin go(page);if(!control_status[60])click();click();repeat(steps)step(up);back();end endtask
 task samples(input integer n);begin repeat(n)begin @(posedge pcm_valid);@(negedge clk);end end endtask
 function[31:0]event_word(input bit hand,input integer zone,id);
  event_word={2'b00,hand,zone[3:0],2'b00,2'b00,7'd100,2'b11,id[7:0],4'd0};
 endfunction
 task hit(input bit hand,input integer zone,id);
 begin
  @(negedge clk);payload[hand*32+:32]=event_word(hand,zone,id);push_valid=1<<hand;#1;
  if(!accepted[hand])$fatal(1,"hit not accepted");@(negedge clk);push_valid=0;repeat(1500)@(negedge clk);
 end endtask
 reg old_ws=0,decoding=0;integer bits=0,words=0,nonzero=0,left_only=0;
 reg[15:0]word=0,held_l=0,held_r=0;
 always @(negedge bck)begin #1;if(dut.dac.slot==1 && rst_n)begin held_l=dut.dac.held_left;held_r=dut.dac.held_right;end end
 always @(posedge bck or negedge rst_n)if(rst_n)begin
  if(ws!=old_ws)begin if(decoding && bits!=16)$fatal(1,"menu DAC bit length");old_ws=ws;bits=0;word=0;decoding=1;end
  if(decoding)begin word={word[14:0],dout};bits++;if(bits==16)begin
   if(word!==(ws ? held_l : held_r))$fatal(1,"menu PCM differs from serial word");words++;if(word!=0)nonzero++;
   if(ws && word!=0 && held_r==0)left_only++;
  end end
 end else begin old_ws=0;decoding=0;bits=0;word=0;end
 function signed[15:0]limit16(input integer n);limit16=n>32767 ? 32767 : n< -32768 ? -32768 : n;endfunction
 integer reference_left,reference_right;
 always @(negedge clk)if(rst_n && dut.sample_valid)begin
  reference_left=0;reference_right=0;
  for(integer v=0;v<32;v++)begin
   if(v<16)reference_left+=$signed(voice_samples[v*16+:16]);
   else reference_right+=$signed(voice_samples[v*16+:16]);
  end
  if(dut.dry_left!==limit16(reference_left>>>3) || dut.dry_right!==limit16(reference_right>>>3))$fatal(1,"independent bank mix reference");
 end
 function[31:0]full_word(input bit hand,input integer index);
  reg[31:0]w;
  begin
   w=event_word(hand,index%12,index+16);w[24:23]=2;w[20:14]=40;
   w[22:21]=hand ? (index<12 ? 2'b00 : 2'b01) : (index<12 ? 2'b10 : 2'b11);
   full_word=w;
  end
 endfunction
 integer lc,rc;reg[31:0]right_epoch;
 initial begin
  repeat(6)@(negedge clk);rst_n=1;samples(2);
  if(!control_status[6] || !amplifier_off)$fatal(1,"default mute");
  edit(1,1,1);edit(2,1,1); // left bass, 1.5s release
  edit(9,1,0);samples(260);
  if(control_status[6] || master_gain!=256 || amplifier_off)$fatal(1,"menu mute not connected to gain");
  hit(0,3,1);samples(80);
  if(dut.instrument.audio.preset[0]!=1 || dut.instrument.audio.tail[0]!=2 || notes[6:0]!=65 || !gates[0])$fatal(1,"menu note snapshot not applied");
  if(pcm_right!=0 || left_only<10)$fatal(1,"single left hand leaked into right");
  edit(1,2,1);edit(2,2,0); // next left notes bell + short tail
  if(dut.instrument.audio.preset[0]!=1 || dut.instrument.audio.tail[0]!=2)$fatal(1,"editing mutated sounding note");
  hit(0,4,2);samples(30);
  if(dut.instrument.audio.preset[1]!=3 || dut.instrument.audio.tail[1]!=0 || notes[7+:7]!=67)$fatal(1,"new left parameters not sampled");
  edit(0,1,1);edit(1,2,1); // right wind
  hit(1,5,3);samples(30);
  if(dut.instrument.audio.preset[BANK]!=2 || dut.instrument.audio.tail[BANK]!=1 || notes[BANK*7+:7]!=69)$fatal(1,"right menu ownership");
  @(negedge clk);pedal_toggle=1;@(negedge clk);pedal_toggle=0;@(negedge clk);
  hit(0,0,4);hit(1,6,5);samples(30);lc=0;rc=0;
  for(integer v=0;v<32;v++)if(gates[v])begin if(v<16)lc++;else rc++;end
  if(lc!=5 || rc!=2 || !control_status[7])$fatal(1,"pedal did not affect only future left triad: %0d/%0d",lc,rc);
  if(dut.instrument.audio.preset[0]!=1 || dut.instrument.audio.tail[0]!=2)$fatal(1,"pedal/edit altered old note");
  edit(3,3,1);edit(4,1,1);edit(5,79,0);edit(6,10,0);edit(7,1,1);samples(600);
  if(active_effect!=3 || active_delay!=48 || actual_wet!=144 || active_feedback!=0 || active_depth!=112 || transitioning)$fatal(1,"menu effect parameters not active");
  right_epoch=epochs[63:32];
  @(negedge clk);wrist_short=1;@(negedge clk);wrist_short=0;samples(40);
  if(epochs[31:0]!=1 || epochs[63:32]!=right_epoch || gates[15:0]!=0 || !gates[BANK])$fatal(1,"left calibrate cancellation leaked to right");
  // Disabling the right IMU purges only its bank and prevents new queue writes.
  @(negedge clk);imu_enabled=1;samples(40);
  if(gates[31:16]!=0 || epochs[63:32]!=right_epoch+1)$fatal(1,"disable did not release right");
  @(negedge clk);push_valid=2;#1;if(accepted[1])$fatal(1,"disabled input accepted");@(negedge clk);push_valid=0;
  edit(9,1,1);samples(270);
  if(!amplifier_off || pcm_left || pcm_right || master_gain)$fatal(1,"menu final mute");
  if(underflows || invalid_events || stereo_clips || fx_drops || fx_clips || event_drops || stolen_notes || words<2000 || nonzero<200)$fatal(1,"menu performance errors/coverage");
  // Full default Voice capacity, 32 different MIDI notes, maximum menu reverb
  // feedback/wet, while live per-hand expression refreshes config messages.
  @(negedge clk);rst_n=0;imu_enabled=3;repeat(6)@(negedge clk);rst_n=1;samples(2);
  edit(1,2,1);edit(0,1,1);edit(1,2,1);
  edit(3,3,1);edit(4,8,1);edit(5,79,0);edit(6,6,1);edit(9,1,0);samples(600);
  for(integer n=0;n<16;n++)begin
   @(negedge clk);payload={full_word(1,n),full_word(0,n)};push_valid=3;#1;
   if(accepted!=3)$fatal(1,"full capacity push");@(negedge clk);push_valid=0;repeat(2000)@(negedge clk);
  end
  samples(30);
  if(gates!=32'hffffffff || active_voices!=32'hffffffff)$fatal(1,"32 notes not simultaneously active");
  for(integer v=0;v<32;v++)begin
   if(notes[v*7+:7]!=(v<16 ? 36+v : 60+v-16))$fatal(1,"full capacity note identity %0d",v);
   for(integer w=0;w<v;w++)if(notes[v*7+:7]==notes[w*7+:7])$fatal(1,"duplicate full capacity pitch");
  end
  bend_cents={16'(-50),16'd75};brightness=16'hd040;samples(1000);
  if(gates!=32'hffffffff || active_effect!=3 || actual_wet!=255 || active_feedback!=128 || transitioning)$fatal(1,"full load effect state");
  if(underflows || invalid_events || stereo_clips || fx_drops || fx_clips || event_drops || stolen_notes || max_render_cycles>=1000)$fatal(1,"full load lost sample/deadline");
  edit(9,1,1);samples(270);
  if(!amplifier_off || pcm_left || pcm_right)$fatal(1,"full load mute");
  $display("TB_PASS canonical semantic menu -> actual 32 Voice/16384 FX/PT8211: per-hand next-note tone/release snapshot, pedal future triad, actual effect delay/wet/feedback/depth, calibration/disable ownership, 32 unique concurrent notes + wet255 feedback128 reverb + live expression, independent golden bank sums, mute ramp, %0d serial words %0d nonzero max render %0d clocks",words,nonzero,max_render_cycles);$finish;
 end
 initial begin #140000000;$fatal(1,"menu performance watchdog");end
endmodule
