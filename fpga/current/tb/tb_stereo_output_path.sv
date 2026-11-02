`timescale 1ns/1ps
// Default production-size FX and actual fractional 48kHz PT8211 serializer.
module tb_stereo_output_path;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,in_valid=0,muted=1;
 reg signed[15:0]in_left=0,in_right=0;reg[1:0]requested_mode=0,clear_history=0;reg[7:0]requested_wet=128;
 wire signed[15:0]pcm_left,pcm_right;wire pcm_valid;wire[1:0]active_mode;wire[7:0]actual_wet;
 wire[8:0]master_gain;wire amplifier_off;wire[31:0]fx_drops,fx_clips;
 wire input_accepted;reg[8:0]test_gain=8; stereo_output_path dut(.*);
 wire bck,ws,dout,sample_tick;
 pt8211_output dac(.clk(clk),.rst_n(rst_n),.pcm_left(pcm_left),.pcm_right(pcm_right),.*);
 task send(input integer l,r,expect_l,expect_r);
 begin
  expect_l=(expect_l+(expect_l<0 ? 15 : 16))>>>5;expect_r=(expect_r+(expect_r<0 ? 15 : 16))>>>5;
  @(posedge sample_tick);repeat(400)@(negedge clk);in_left=l;in_right=r;in_valid=1;
  @(negedge clk);in_valid=0;wait(pcm_valid);@(negedge clk);
  if(pcm_left!==expect_l[15:0] || pcm_right!==expect_r[15:0])$fatal(1,"stereo path expected %0d/%0d got %0d/%0d",expect_l,expect_r,pcm_left,pcm_right);
 end endtask
 reg old_ws=0;reg[15:0]word=0,held_l=0,held_r=0;integer bits=0,words=0,different=0;bit decoding=0;
 always @(negedge bck)begin #1;if(dac.slot==1 && rst_n)begin held_l=dac.held_left;held_r=dac.held_right;if(held_l!=held_r)different++;end end
 always @(posedge bck)if(rst_n)begin
  if(ws!=old_ws)begin if(decoding && bits!=16)$fatal(1,"DAC bit length");old_ws=ws;bits=0;word=0;decoding=1;end
  if(decoding)begin word={word[14:0],dout};bits++;if(bits==16)begin
   if(word!==(ws ? held_l : held_r))$fatal(1,"independent serial DAC word %h",word);words++;
  end end
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  send(10000,-6000,0,0);if(!amplifier_off || master_gain!=0)$fatal(1,"unsafe muted reset");
  muted=0;
  for(integer n=0;n<8;n++)send(10000,-6000,(10000*n)>>>3,(-6000*n)>>>3);
  send(-32768,32767,-32768,32767);if(master_gain!=8 || amplifier_off)$fatal(1,"gain ramp");
  // The mouse gain ramp is only eight samples; exercise sustained stereo too.
  repeat(128)send(10000,-6000,10000,-6000);
  send(1,-1,0,0); // symmetric rounding must not leave a negative 1-LSB floor.
  repeat(960)send(0,0,0,0);
  if(amplifier_off)$fatal(1,"amplifier toggled between notes");
  send(10000,-6000,10000,-6000);
  if(amplifier_off)$fatal(1,"valid audio did not re-enable amplifier");
  // Changing dry/wet modes clears all old history at zero wet, preserving dry audio.
  requested_mode=1;repeat(300)send(0,0,0,0);
  if(active_mode!=1 || actual_wet!=128)$fatal(1,"delay mode failed to settle");
  send(10000,0,5000,0);
  for(integer n=1;n<=4800;n++)send(0,0,n==4800 ? 5000 : 0,0);
  // Clear just left history. A right echo must remain valid while left feedback disappears.
  send(0,-6000,0,-3000);
  @(negedge clk);clear_history=1;@(negedge clk);clear_history=0;
  for(integer n=1;n<=4800;n++)send(0,0,0,n==4800 ? -3000 : 0);
  requested_mode=3;
  for(integer n=0;n<129;n++)begin
   send(0,0,0,0);
   if(n<128 && (active_mode!=1 || actual_wet!=127-n))$fatal(1,"mode switched before wet drained");
  end
  if(active_mode!=3 || actual_wet!=0)$fatal(1,"mode transition at zero wet");
  repeat(4000)send(0,0,0,0); // old feedback must not reappear on new reverb taps.
  requested_mode=2;repeat(300)send(0,0,0,0);
  if(active_mode!=2 || actual_wet!=128)$fatal(1,"chorus mode");
  requested_mode=0;repeat(300)send(0,0,0,0);
  if(active_mode!=0 || actual_wet!=0)$fatal(1,"bypass restore");
  muted=1;for(integer n=8;n>0;n--)send(10000,-6000,(10000*n)>>>3,(-6000*n)>>>3);
  send(10000,-6000,0,0);
  test_gain=256;muted=0;
  for(integer n=0;n<256;n++)send(16384,-16384,(16384*n)>>>3,(-16384*n)>>>3);
  send(16384,-16384,16384*32,-16384*32);
  if(master_gain!=256 || pcm_left!=16384 || pcm_right!=-16384)$fatal(1,"full-scale gain width/sign");
  repeat(960)send(0,0,0,0);
  muted=1;for(integer n=256;n>0;n--)send(0,0,0,0);send(0,0,0,0);
  if(!amplifier_off || fx_drops || fx_clips || words<20000 || different<100)$fatal(1,"drop/clip/serializer coverage off=%d drops=%d clips=%d words=%d different=%d",amplifier_off,fx_drops,fx_clips,words,different);
  $display("TB_PASS DUO02 default stereo FX -> mute ramp -> actual PT8211, independent signed channels, 4800-sample delay impulses, per-hand history clear, mode drain/clear/reverb/chorus/bypass, %0d serial words",words);$finish;
 end
 initial begin #400000000;$fatal(1,"stereo path watchdog");end
endmodule

