`timescale 1ns/1ps
module tb_piano_tail;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0,config_valid=0,piano_config_valid=0;
 reg [135:0] config_data=0;reg [31:0] piano_config_data=0;
 wire [79:0] samples;wire sample_valid;wire [31:0] clips;
 audio_core dut(.*);
 integer n,cycles;reg signed [15:0] v;integer positive=0,negative=0;
 task rounding(input signed [49:0] product,input integer expected,input integer wave_id);
 begin
  @(negedge clk);dut.state=3;dut.voice=0;dut.wave[0]=wave_id;dut.prod2=product;
  @(negedge clk);v=dut.voice_value;
  if(v!==16'(expected))$fatal(1,"round product=%d expected=%d actual=%d",product,expected,v);
  dut.state=0;
 end
 endtask
 task step;
 begin
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
  while(!sample_valid)begin @(negedge clk);cycles=cycles+1;if(cycles>70)$fatal(1,"sample deadline");end
 end
 endtask
 initial begin
  #100;rst_n=1;
  rounding(50'sd2104533975,0,4);rounding(-50'sd2104533975,0,4); // +/-0.49
  rounding(50'sd2147483648,1,4);rounding(-50'sd2147483648,-1,4);
  rounding(50'sd6442450944,2,4);rounding(-50'sd6442450944,-2,4);
  rounding(50'sd6442450943,1,4);rounding(-50'sd6442450943,-1,4);
  rounding(-50'sd2104533975,-1,0); // Basic wave behavior stays bit-identical.
  // Exercise the real oscillator/envelope/gain pipeline at sub-half-LSB energy.
  @(negedge clk);dut.wave[0]=4;dut.gate[0]=1;dut.old_gate[0]=1;dut.old_wave[0]=4;
  dut.stage[0]=2;dut.env[0]=45874;dut.sustain[0]=45874;dut.gain[0]=131;
  dut.piano_body[0]=24'd100000;dut.piano_bright[0]=0;dut.piano_fraction[0]=0;
  repeat(256)begin step();if(samples!==0)$fatal(1,"sub-half PCM tail is not silent %h",samples);end
  // Still resolve both polarities above threshold; never mute a live quiet note.
  dut.piano_body[0]=24'd1000000;
  repeat(256)begin step();v=samples[15:0];if(v>0)positive=positive+1;if(v<0)negative=negative+1;end
  if(positive<20 || negative<20)$fatal(1,"low-level note lost polarity %d %d",positive,negative);
  // Repeated off/on edges all reinitialize the body, without hold.
  for(n=0;n<10;n=n+1)begin
   @(negedge clk);dut.gate[0]=0;step();
   @(negedge clk);dut.gate[0]=1;step();
   if(dut.piano_body[0]<24'hff0000)$fatal(1,"missing note-on %d",n);
  end
  $display("TB_PASS symmetric piano rounding, sub-half-LSB silence, low-level polarity, ten note-on edges, basic wave unchanged");$finish;
 end
 initial begin #10000000;$fatal(1,"watchdog");end
endmodule
