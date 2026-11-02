`timescale 1ns/1ps
// Cycle-accurate equivalence to the scheduler before physical write predecode.
module tb_scheduler_predecode;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,event_valid=0,config_ready=0,chord_mode=0;
 reg[63:0]event_data=0,epochs=0;
 reg[1:0]release_pending=0,mono_glide=0;
 reg[31:0]bend_cents=0,vibrato_cents=0;
 reg[127:0]envelopes=0;reg[7:0]release_due=0;
 wire event_ready,config_valid,committed,committed_hand;
 wire[127:0]config_data;wire[1:0]release_ack;
 wire[63:0]voice_brightness;wire[7:0]owned,gates,committed_id;
 wire[55:0]notes;wire[31:0]invalid_events,stolen_notes;
 wire ref_ready,ref_valid,ref_committed,ref_hand;
 wire[127:0]ref_data;wire[1:0]ref_ack;
 wire[63:0]ref_brightness;wire[7:0]ref_owned,ref_gates,ref_id;
 wire[55:0]ref_notes;wire[31:0]ref_invalid,ref_stolen;
 dual_voice_scheduler #(.VOICES(8)) dut(
 .clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
 .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),
 .chord_mode(chord_mode),.preset_ids(6'b011010),.release_ids(4'b0101),
 .hold_ticks_left(32'd72000),.hold_ticks_right(32'd96000),.mono_glide(mono_glide),
 .bend_cents(bend_cents),.vibrato_cents(vibrato_cents),.brightness(16'h7f80),
 .envelopes(envelopes),.release_due(release_due),.config_valid(config_valid),
 .config_data(config_data),.config_ready(config_ready),.voice_brightness(voice_brightness),
 .owned(owned),.gates(gates),.notes(notes),.invalid_events(invalid_events),.stolen_notes(stolen_notes),
 .committed(committed),.committed_id(committed_id),.committed_hand(committed_hand));
 dual_voice_scheduler_predecode #(.VOICES(8)) reference(
 .clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_ready(ref_ready),.event_data(event_data),
 .release_pending(release_pending),.release_ack(ref_ack),.epochs(epochs),
 .chord_mode(chord_mode),.preset_ids(6'b011010),.release_ids(4'b0101),
 .hold_ticks_left(32'd72000),.hold_ticks_right(32'd96000),.mono_glide(mono_glide),
 .bend_cents(bend_cents),.vibrato_cents(vibrato_cents),.brightness(16'h7f80),
 .envelopes(envelopes),.release_due(release_due),.config_valid(ref_valid),
 .config_data(ref_data),.config_ready(config_ready),.voice_brightness(ref_brightness),
 .owned(ref_owned),.gates(ref_gates),.notes(ref_notes),.invalid_events(ref_invalid),.stolen_notes(ref_stolen),
 .committed(ref_committed),.committed_id(ref_id),.committed_hand(ref_hand));
 reg[31:0]rng=32'h613ec9a7;integer cycle,j,accepted_count=0,cancel_count=0;
 always @(posedge clk)if(rst_n)begin
  if(event_valid && event_ready)accepted_count<=accepted_count+1;
  for(integer v=0;v<8;v++)begin
   if(gates[v])envelopes[v*16+:16]<=16'h8000;
   else envelopes[v*16+:16]<=envelopes[v*16+:16]>16'h2000 ? envelopes[v*16+:16]-16'h2000 : 0;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(cycle=0;cycle<40000;cycle++)begin
   @(negedge clk);
   if({event_ready,config_valid,config_data,release_ack,owned,gates,notes,invalid_events,stolen_notes,committed,committed_id,committed_hand} !==
      {ref_ready,ref_valid,ref_data,ref_ack,ref_owned,ref_gates,ref_notes,ref_invalid,ref_stolen,ref_committed,ref_id,ref_hand})
    $fatal(1,"predecode changed scheduler cycle %d",cycle);
   for(j=0;j<8;j++)if(dut.revision[j]!==reference.revision[j] || dut.ftw[j]!==reference.ftw[j] || dut.gain[j]!==reference.gain[j])
    $fatal(1,"bank write mismatch voice %d cycle %d",j,cycle);
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   config_ready=rng[0] || rng[1];
   if(event_ready)event_valid=0;
   if(!event_valid && rng[3:2]==0)begin
    event_valid=1;event_data=0;
    event_data[29]=rng[4];event_data[28:25]=rng[7:5]%7;
    event_data[31:30]=rng[10:8]==0 ? 1 : 0;
    event_data[63:32]=rng[4] ? epochs[63:32] : epochs[31:0];
    event_data[20:14]=rng[17:11] | 7'd1;event_data[11:4]=rng[23:20];
   end
   for(j=0;j<2;j++)begin
    if(release_ack[j])release_pending[j]=0;
    else if(!release_pending[j] && rng[19:12]==j)begin
     release_pending[j]=1;epochs[j*32+:32]=epochs[j*32+:32]+1;cancel_count=cancel_count+1;
    end
   end
   release_due=0;
   if(rng[26:24]==0)release_due[rng[29:27]]=1;
   if(cycle%113==0)begin chord_mode=rng[30];mono_glide=rng[17:16];end
   if(cycle%131==0)begin bend_cents={16'(rng[7:0]%201-100),16'(rng[15:8]%201-100)};vibrato_cents={16'(rng[3:0]),16'(rng[7:4])};end
  end
  if(accepted_count<100 || cancel_count<10 || stolen_notes==0)$fatal(1,"insufficient stress coverage %d/%d/%d",accepted_count,cancel_count,stolen_notes);
  $display("TB_PASS scheduler cycle equivalence: accepted %d, cancellations %d, steals %d; chord, gain, expiry, expression, mono and backpressure",accepted_count,cancel_count,stolen_notes);$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
