`timescale 1ns/1ps
// The four production timbres must remain cycle- and bit-identical even during
// long quiet release tails, repeated triggers, expiration and forced release.
module tb_route27_state_ram;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0,config_valid=0;reg[127:0]config_data=0;
 integer phase=0;
 always @(posedge clk)begin
  sample_tick<=0;
  if(rst_n)begin if(phase==1040)begin phase<=0;sample_tick<=1;end else phase<=phase+1;end
 end
 wire[79:0]samples,ref_samples;wire sample_valid,ref_valid,ready,ref_ready;
 wire[127:0]envs,ref_envs,voice_values,ref_values;
 wire[7:0]release_due,ref_due,active,ref_active;wire[31:0]clips,ref_clips,underflows,ref_underflows;
 wire signed[15:0]left,right,ref_left,ref_right;wire[15:0]max_render,ref_max;
 dual_audio_core #(.VOICES(8),.FOUR_TIMBRES_ONLY(1)) dut(.clk(clk),.rst_n(rst_n),
 .sample_tick(sample_tick),.config_valid(config_valid),.config_data(config_data),
 .samples(samples),.sample_valid(sample_valid),.clips(clips),.config_ready(ready),
 .local_brightness(64'h9070605080706050),.all_notes({7'd64,7'd67,7'd69,7'd72,7'd60,7'd62,7'd64,7'd65}),
 .hold_samples({32'd80,32'd55}),.release_due(release_due),.all_envelopes(envs),
 .voice_samples(voice_values),.active_voices(active),.underflows(underflows),
 .stereo_left(left),.stereo_right(right),.max_render_cycles(max_render),
 .piano_hold(2'b0),.piano_coefficients(32'd134),.glide_coefficients(48'b0),.vibrato_ratios({20'd65536,20'd65536}));
 dual_audio_core_route27_reference #(.VOICES(8),.FOUR_TIMBRES_ONLY(1)) reference(.clk(clk),.rst_n(rst_n),
 .sample_tick(sample_tick),.config_valid(config_valid),.config_data(config_data),
 .samples(ref_samples),.sample_valid(ref_valid),.clips(ref_clips),.config_ready(ref_ready),
 .local_brightness(64'h9070605080706050),.all_notes({7'd64,7'd67,7'd69,7'd72,7'd60,7'd62,7'd64,7'd65}),
 .hold_samples({32'd80,32'd55}),.release_due(ref_due),.all_envelopes(ref_envs),
 .voice_samples(ref_values),.active_voices(ref_active),.underflows(ref_underflows),
 .stereo_left(ref_left),.stereo_right(ref_right),.max_render_cycles(ref_max),
 .piano_hold(2'b0),.piano_coefficients(32'd134),.glide_coefficients(48'b0),.vibrato_ratios({20'd65536,20'd65536}));
 integer frame=0,tail_frames=0;
 reg[79:0]saved_samples;reg[127:0]saved_envs,saved_values;reg[7:0]saved_active;reg signed[15:0]saved_left,saved_right;reg[31:0]saved_clips;integer reference_frame=0;
 always @(negedge clk)if(rst_n)begin
  if(ref_valid)begin
   reference_frame=reference_frame+1;saved_samples=ref_samples;saved_envs=ref_envs;saved_values=ref_values;saved_active=ref_active;saved_left=ref_left;saved_right=ref_right;saved_clips=ref_clips;
  end
  if(sample_valid)begin
   frame=frame+1;
   if(frame!=reference_frame || {samples,envs,voice_values,active,left,right,clips} !== {saved_samples,saved_envs,saved_values,saved_active,saved_left,saved_right,saved_clips})$fatal(1,"state RAM PCM/envelope mismatch frame %d",frame);
   if(dut.release_count[0]!=0)tail_frames=tail_frames+1;
  end
 end
 task configure(input integer voice,kind,coefficient,input gate_on,trigger,fast);
 begin wait(ready && ref_ready);@(negedge clk);config_data=0;config_data[7:0]=voice;
 config_data[39:8]=32'd26000000+voice*32'd1200000;
 config_data[47:40]=120+voice*13;config_data[51:50]=kind;
 config_data[55]=1;config_data[56]=gate_on;config_data[57]=1;config_data[58]=trigger;config_data[59]=fast;
 config_data[79:64]=5000;config_data[95:80]=31;config_data[111:96]=32000;config_data[127:112]=coefficient;
 config_valid=1;@(negedge clk);config_valid=0;end endtask
 initial begin
  // The renderer runs one extra read clock per voice. Equal excitation noise
  // isolates state-storage equivalence from the free-running PRNG time phase.
  force dut.models.noise=32'h13579bdf;force reference.models.noise=32'h13579bdf;
  repeat(4)@(negedge clk);rst_n=1;
  for(integer v=0;v<8;v++)configure(v,v%4,v==0 ? 1 : v==1 ? 60000 : 134,1,1,0);
  wait(frame>=25);for(integer v=0;v<8;v++)configure(v,v%4,v==0 ? 1 : v==1 ? 60000 : 134,0,0,0);
  wait(frame>=65);configure(3,3,134,1,1,0);configure(4,0,134,1,1,0);
  wait(frame>=90);configure(4,0,134,0,0,1);
  wait(frame>=300);
  if(tail_frames<100 || underflows || max_render>=1040)$fatal(1,"release stress coverage/budget");
  @(negedge clk);rst_n=0;repeat(5)@(negedge clk);rst_n=1;repeat(3)@(posedge sample_valid);@(negedge clk);
  if(active || underflows)$fatal(1,"old RAM state leaked after warm reset");
  $display("TB_PASS synchronous state RAM sample equivalence vs frozen register renderer (four timbres; equal excitation noise), %d frames, %d quiet-tail frames, repeated trigger/expiry/fast release, max render %d",frame,tail_frames,max_render);$finish;
 end
 initial begin #15000000;$fatal(1,"timeout");end
endmodule
`include "tb/reference/dual_audio_core_route27_reference.v"
