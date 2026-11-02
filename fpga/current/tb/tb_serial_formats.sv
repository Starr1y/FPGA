`timescale 1ns/1ps
module tb_serial_formats;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0;reg[15:0]pcm_left=0,pcm_right=0;
 wire bck,ws,dout,sample_tick,i2s_bck,i2s_ws,i2s_dout;
 wire gb,gw,gd,gt;
 stereo_serial_output dut(.*);
 pt8211_output golden(.clk(clk),.rst_n(rst_n),.pcm_left(pcm_left),.pcm_right(pcm_right),.bck(gb),.ws(gw),.dout(gd),.sample_tick(gt));
 integer ticks=0,words=0;reg old_ws=0,word_ws=0;reg acquired=0;integer bits=0;
 reg[15:0]word=0;reg[15:0]expected_left=0,expected_right=0;
 always @(negedge clk)if(rst_n)begin
  if({bck,ws,dout,sample_tick}!=={gb,gw,gd,gt})$fatal(1,"PT8211 waveform changed");
  if(i2s_bck!==bck)$fatal(1,"clock mismatch");
 end
 always @(negedge rst_n)begin acquired=0;old_ws=0;bits=0;end
 always @(posedge sample_tick)begin
  ticks=ticks+1;
  expected_left=pcm_left;expected_right=pcm_right;
  // Inputs move during a frame; both transmitted words must remain locked.
  #50;pcm_left=$random;pcm_right=$random;
 end
 always @(posedge i2s_bck)if(rst_n)begin
  // Delayed WS selects this bit: transition itself accompanies prior LSB.
  if(i2s_ws!==old_ws)begin
   if(acquired)begin
    word={word[14:0],i2s_dout};bits=bits+1;
    if(bits!=16)$fatal(1,"I2S word size %d",bits);
    if(word!==(word_ws ? expected_right : expected_left))$fatal(1,"I2S PCM/polarity mismatch %h",word);
    words=words+1;
   end
   acquired=1;bits=0;word=0;word_ws=i2s_ws;
  end else if(acquired)begin word={word[14:0],i2s_dout};bits=bits+1;end
  old_ws=i2s_ws;
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;pcm_left=16'h8000;pcm_right=16'h7fff;
  #10000000;
  if(ticks<479 || ticks>481 || words<950)$fatal(1,"rate %d words %d",ticks,words);
  @(negedge clk);rst_n=0;repeat(8)@(negedge clk);rst_n=1;
  #1000000;
  $display("TB_PASS PT golden cycle equality; Philips I2S 1-bit WS lead, L/R polarity,16-bit stereo,48k,locked pair,reset; ticks=%0d words=%0d",ticks,words);$finish;
 end
endmodule
