`timescale 1ns/1ps
module tb_parameter_stereo_output;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,in_valid=0,muted=1;reg signed[15:0]in_left=0,in_right=0;
 reg[1:0]requested_mode=0,clear_history=0;
 reg[7:0]requested_wet=128,requested_feedback=0,requested_depth=96;reg[13:0]requested_delay=4800;
 wire signed[15:0]pcm_left,pcm_right;wire pcm_valid;wire[1:0]active_mode;
 wire[7:0]actual_wet,active_feedback,active_depth;wire[13:0]active_delay;
 wire transitioning;wire[8:0]master_gain;wire amplifier_off;wire[31:0]fx_drops,fx_clips;
 parameter_stereo_output dut(.*);
 wire bck,ws,dout,sample_tick;
 pt8211_output dac(.clk(clk),.rst_n(rst_n),.pcm_left(pcm_left),.pcm_right(pcm_right),.*);
 integer frames=0,words=0,different=0;reg old_ws=0,decoding=0;
 reg[15:0]word=0,held_l=0,held_r=0;integer bits=0;
 always @(negedge bck)begin #1;if(dac.slot==1 && rst_n)begin held_l=dac.held_left;held_r=dac.held_right;if(held_l!=held_r)different++;end end
 always @(posedge bck)if(rst_n)begin
  if(ws!=old_ws)begin if(decoding && bits!=16)$fatal(1,"DAC bit count");old_ws=ws;bits=0;word=0;decoding=1;end
  if(decoding)begin word={word[14:0],dout};bits++;if(bits==16)begin
   if(word!==(ws ? held_l : held_r))$fatal(1,"serialized stereo word");words++;
  end end
 end
 task send(input integer l,r,expect_l,expect_r);
 begin
  @(posedge sample_tick);repeat(400)@(negedge clk);in_left=l;in_right=r;in_valid=1;
  @(negedge clk);in_valid=0;wait(pcm_valid);@(negedge clk);frames++;
  if(pcm_left!==expect_l[15:0] || pcm_right!==expect_r[15:0])$fatal(1,"frame%0d expected %0d/%0d got %0d/%0d",frames,expect_l,expect_r,pcm_left,pcm_right);
 end endtask
 task settle_zero;begin repeat(300)send(0,0,0,0);if(transitioning)$fatal(1,"parameter transition did not settle");end endtask
 initial begin
  repeat(6)@(negedge clk);rst_n=1;
  send(10000,-6000,0,0);if(!amplifier_off)$fatal(1,"default mute");muted=0;
  for(integer n=0;n<256;n++)send(10000,-6000,(10000*n)>>>8,(-6000*n)>>>8);
  send(-32768,32767,-32768,32767);
  // Exact new user-selected 48-sample echo at full-sized RAM depth.
  requested_mode=1;requested_delay=48;settle_zero();
  send(10000,-6000,5000,-3000);
  for(integer n=1;n<=48;n++)send(0,0,n==48 ? 5000 : 0,n==48 ? -3000 : 0);
  // Tap edits must hold the old tuple until wet reaches zero. Seeded echo has
  // expired with feedback=0, so every transition sample is deterministically zero.
  requested_delay=96;
  for(integer n=0;n<128;n++)begin send(0,0,0,0);if(active_delay!=48 || actual_wet!=127-n)$fatal(1,"tap edit jumped before dry");end
  send(0,0,0,0);if(active_delay!=96 || actual_wet!=0)$fatal(1,"tap commit at zero wet");settle_zero();
  send(0,-6000,0,-3000);
  for(integer n=1;n<=96;n++)send(0,0,0,n==96 ? -3000 : 0);
  // Feedback is bounded and slews independently; no unrelated history clear.
  requested_feedback=255;
  for(integer n=1;n<=192;n++)begin send(0,0,0,0);if(active_feedback!=n)$fatal(1,"feedback slew");end
  send(0,0,0,0);if(active_feedback!=192)$fatal(1,"delay feedback clamp");
  // Prove feedback changes audio: successive echoes must decay by 192/256.
  send(10000,0,5000,0);
  for(integer n=1;n<=288;n++)send(0,0,n==96 ? 5000 : n==192 ? 3750 : n==288 ? 2812 : 0,0);
  @(negedge clk);clear_history=3;@(negedge clk);clear_history=0;
  requested_feedback=0;settle_zero();
  // A left-only clear removes its echo while preserving the right channel.
  send(10000,-6000,5000,-3000);
  @(negedge clk);clear_history=1;@(negedge clk);clear_history=0;
  for(integer n=1;n<=96;n++)send(0,0,0,n==96 ? -3000 : 0);
  // Rapid edits while draining: commit the latest tuple, not a stale queued one.
  requested_mode=2;requested_delay=576;requested_depth=112;
  repeat(64)send(0,0,0,0);
  if(active_mode!=1 || actual_wet!=64)$fatal(1,"first half drain");
  requested_mode=3;requested_delay=48;requested_depth=144;requested_feedback=255;
  repeat(64)send(0,0,0,0);
  if(active_mode!=1 || actual_wet!=0)$fatal(1,"second half drain");send(0,0,0,0);
  if(active_mode!=3 || active_delay!=48 || active_depth!=144 || active_feedback!=0)$fatal(1,"latest tuple not atomic");
  settle_zero();if(active_feedback!=128)$fatal(1,"reverb feedback clamp");
  requested_mode=2;requested_delay=576;requested_feedback=255;settle_zero();
  if(active_feedback!=0 || active_depth!=144)$fatal(1,"chorus feedback must be zero");
  requested_depth=160;settle_zero();if(active_depth!=160)$fatal(1,"depth edit");
  requested_mode=0;settle_zero();if(actual_wet || active_feedback)$fatal(1,"bypass");
  // Numeric boundaries are enforced even if a future caller bypasses the menu.
  requested_delay=0;settle_zero();if(active_delay!=1)$fatal(1,"minimum tap clamp");
  requested_delay=16383;settle_zero();if(active_delay!=16383)$fatal(1,"maximum full RAM tap");
  muted=1;for(integer n=256;n>0;n--)send(10000,-6000,(10000*n)>>>8,(-6000*n)>>>8);
  send(10000,-6000,0,0);
  if(!amplifier_off || fx_drops || fx_clips || words<7000 || different<200)$fatal(1,"output coverage or errors");
  $display("TB_PASS parameter stereo output: default 16384 RAM, 50MHz/48kHz, exact 48/96 sample echoes, wet drain/atomic latest tuple/history clear, feedback slew/clamps, independent hand clear, gain ramp, %0d frames %0d PT8211 words",frames,words);$finish;
 end
 initial begin #160000000;$fatal(1,"parameter output watchdog");end
endmodule
