`timescale 1ns/1ps
// Queue -> scheduler -> actual ADSR/oscillators/mixer at 50MHz and 48kHz enables.
module tb_dual_synth #(parameter VOICES=32);
 localparam BANK=VOICES/2,VB=$clog2(VOICES);
 reg clk=0;always #10 clk=~clk;reg rst_n=0;reg[1:0]push_valid=0,cancel=0;
 reg[63:0]payload=0;wire event_valid,event_ready;wire[63:0]event_data,epochs,drops,cancelled;
 wire[1:0]release_pending,release_ack;wire[1:0]accepted;
 two_hand_event_queue queue(clk,rst_n,push_valid,payload,cancel,release_ack,release_pending,epochs,event_valid,event_ready,event_data,drops,cancelled,accepted);
 reg chord_mode=0;reg[3:0]preset_ids=4'b1000,release_ids=0;
 reg[31:0]bend=0,vibrato=0;reg[15:0]brightness=16'h8080;reg sample_tick=0;
 integer fraction=0;always @(posedge clk)begin
  if(!rst_n)begin fraction<=0;sample_tick<=0;end
  else if(fraction>=50000000-48000)begin fraction<=fraction+48000-50000000;sample_tick<=1;end
  else begin fraction<=fraction+48000;sample_tick<=0;end
 end
 wire[79:0]samples;wire sample_valid;wire[31:0]clips,underflows,invalid_events,stolen;
 wire[VOICES-1:0]owned,gates,active;wire[VOICES*7-1:0]notes;wire[VOICES*16-1:0]envelopes,voice_samples;
 wire[15:0]max_cycles,monitor_env;wire[31:0]monitor_freq;wire[1:0]monitor_stage;reg[VB-1:0]monitor=0;
 two_hand_synth #(.VOICES(VOICES),.HOLD_TICKS(25000000)) dut(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
  .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.chord_mode(chord_mode),.preset_ids(preset_ids),.release_ids(release_ids),
  .bend_cents(bend),.vibrato_cents(vibrato),.brightness(brightness),.samples(samples),.sample_valid(sample_valid),.clips(clips),.underflows(underflows),
  .owned(owned),.gates(gates),.active_voices(active),.notes(notes),.envelopes(envelopes),.voice_samples(voice_samples),
  .invalid_events(invalid_events),.stolen_notes(stolen),.max_render_cycles(max_cycles),.monitor_voice(monitor),.monitor_frequency(monitor_freq),.monitor_envelope(monitor_env),.monitor_stage(monitor_stage));
 function[31:0]event_word(input bit hand,input integer zone,profile,id,velocity,kind);
  begin event_word={kind[1:0],hand,zone[3:0],profile[1:0],2'b00,velocity[6:0],2'b11,id[7:0],4'd0};end
 endfunction
 task pair(input integer lzone,lprofile,lid,rzone,rprofile,rid,velocity,kind);
  begin @(negedge clk);payload={event_word(1,rzone,rprofile,rid,velocity,kind),event_word(0,lzone,lprofile,lid,velocity,kind)};
   push_valid=3;@(negedge clk);if(accepted!=3)$fatal(1,"pair push not accepted");push_valid=0;end
 endtask
 task single(input bit hand,input integer zone,profile,id,velocity,kind);
  begin @(negedge clk);payload[hand*32+:32]=event_word(hand,zone,profile,id,velocity,kind);push_valid=1<<hand;
   @(negedge clk);if(!accepted[hand])$fatal(1,"single push not accepted");push_valid=0;end
 endtask
 task capacity_pair(input integer i);
  begin @(negedge clk);
   payload={event_word(1,(i+4)%12,2,i+10,80,0),event_word(0,i%12,2,i+10,80,0)};
   payload[22:21]=i<12 ? -1 : 0;payload[54:53]=i<8 ? 0 : 1;
   push_valid=3;@(negedge clk);if(accepted!=3)$fatal(1,"capacity push not accepted");push_valid=0;
  end
 endtask
 task settle;begin repeat(1500)@(negedge clk);end endtask
 task wait_samples(input integer n);begin repeat(n)begin @(posedge sample_valid);@(negedge clk);end end endtask
 task frequency(input integer voice,note,cents);
  real expected;begin monitor=voice;#1;expected=4294967296.0*440.0*$pow(2.0,(note-69)/12.0+cents/1200.0)/48000.0;
   if($abs(monitor_freq-expected)>expected*0.00003+2)$fatal(1,"frequency voice%0d note%0d cents%0d got%0d expect%f",voice,note,cents,monitor_freq,expected);end
 endtask
 integer nonzero=0,sample_count=0;reg held_valid=0;reg[127:0]held_config;
 always @(posedge clk)if(rst_n)begin
  if(held_valid && (!dut.config_valid || dut.config_data!==held_config))$fatal(1,"config changed under backpressure");
  held_valid=dut.config_valid && !dut.config_ready;held_config=dut.config_data;
  if(sample_valid)begin sample_count++;if(samples[79:64]!=0)nonzero++;end
  for(integer h=0;h<2;h++)if(release_ack[h])begin
   for(integer i=h*BANK;i<(h+1)*BANK;i++)if(dut.audio.gate[i])$fatal(1,"release ACK before actual audio gate off");
  end
 end else held_valid=0;
 reg[31:0]right_freq;reg[15:0]release_env;integer count;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  pair(6,0,7,10,2,7,80,0);settle();
  if(notes[6:0]!=71 || notes[BANK*7+:7]!=70 || !gates[0] || !gates[BANK])$fatal(1,"four-bit mapping/bank allocation");
  frequency(0,71,0);frequency(BANK,70,0);
  single(0,6,0,7,120,1);settle();
  if(dut.audio.gain[0]!=60 || dut.audio.gain[BANK]!=40)$fatal(1,"same-ID velocity update crossed hands");
  bend[15:0]=100;brightness[7:0]=220;settle();frequency(0,71,100);frequency(BANK,70,0);
  if(dut.scheduler.voice_brightness[7:0]!=220 || dut.scheduler.voice_brightness[BANK*8+:8]!=128)$fatal(1,"brightness crossed hands");
  wait_samples(300);if(nonzero==0 || envelopes[15:0]==0 || envelopes[BANK*16+:16]==0)$fatal(1,"real synthesizer silent");
  right_freq=dut.audio.freq[BANK];release_env=envelopes[15:0];
  @(negedge clk);cancel=1;@(negedge clk);cancel=0;wait(!release_pending[0]);settle();
  if(gates[0] || dut.audio.gate[0] || !gates[BANK] || dut.audio.freq[BANK]!=right_freq)$fatal(1,"group cancellation crossed hands");
  wait_samples(100);if(envelopes[15:0]>=release_env || envelopes[15:0]==0)$fatal(1,"cancel did not retain smooth release tail");
  single(0,0,1,8,80,0);settle();frequency(1,60,100);
  // Mode is sampled on note acceptance, never retunes an existing Voice.
  chord_mode=1;settle();frequency(BANK,70,0);
  single(0,1,0,9,80,0);wait_samples(30);settle();
  count=0;for(integer i=0;i<BANK;i++)if(dut.scheduler.ids[i]==9 && owned[i])begin
   if(notes[i*7+:7]!=62 && notes[i*7+:7]!=65 && notes[i*7+:7]!=69)$fatal(1,"diatonic chord interval");count++;
  end
  if(count!=3)$fatal(1,"triad did not allocate three owned Voices");
  single(0,1,0,9,100,1);settle();
  for(integer i=0;i<BANK;i++)if(dut.scheduler.ids[i]==9 && dut.audio.gain[i]!=50)$fatal(1,"chord strength group update missing");
  frequency(BANK,70,0);
  // Interrupt a held note-on config: it must drain unchanged, then release.
  wait(dut.audio.state!=0);single(0,2,0,20,80,0);
  wait(dut.config_valid && !dut.config_ready);
  @(negedge clk);cancel=1;@(negedge clk);cancel=0;
  wait(!release_pending[0]);settle();
  for(integer i=0;i<BANK;i++)if(dut.audio.gate[i])$fatal(1,"held-config cancellation left a live Voice");
  frequency(BANK,70,0);
  // Reset only the digital test environment before the full capacity trial.
  @(negedge clk);rst_n=0;repeat(5)@(negedge clk);rst_n=1;chord_mode=0;bend=0;brightness=16'h8080;
  for(integer i=0;i<BANK;i++)begin capacity_pair(i);settle();end
  wait_samples(300);
  if(owned!={VOICES{1'b1}} || active!={VOICES{1'b1}} || stolen!=0 || drops!=0 || underflows!=0)$fatal(1,"full-capacity rendering failed");
  for(integer i=0;i<VOICES;i++)frequency(i,i<BANK ? 48+i : 64+i-BANK,0);
  // One further note reclaims/fades only its own bank, without changing peer ownership.
  single(0,11,2,200,100,0);repeat(10000)@(negedge clk);
  if(stolen!=1 || dut.scheduler.ids[0]!=200 || dut.scheduler.ids[BANK]!=10 || !gates[BANK])$fatal(1,"steal mixed ownership");
  frequency(0,71,0);frequency(BANK,64,0);
  // Reject invalid profile and fourth event kind without producing a new Voice.
  single(1,15,3,210,80,0);single(1,0,0,211,80,3);settle();
  if(invalid_events!=2 || underflows!=0 || drops!=0)$fatal(1,"invalid events/stall accounting");
  $display("TB_PASS %0d Voices: queue to real PCM, 7/5/12 mapping, same-ID hand isolation, triad/mode snapshot, per-hand expression, release ACK at actual audio gates, natural tails, full capacity and own-bank faded steal; %0d samples max %0d clocks, digital only",VOICES,sample_count,max_cycles);$finish;
 end
 initial begin #100000000;$fatal(1,"synth watchdog");end
endmodule
