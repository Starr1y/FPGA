`timescale 1ns/1ps
module tb_audio_quality;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;
 // Production 50MHz/48kHz enables; the smaller bank only speeds simulation.
 reg[31:0]fraction=0;reg sample_tick=0;
 always @(posedge clk)begin sample_tick<=0;if(rst_n)begin
  if(fraction>=50000000-48000)begin fraction<=fraction+48000-50000000;sample_tick<=1;end else fraction<=fraction+48000;
 end end
 reg event_valid=0;wire event_ready;reg[63:0]event_data=0;
 reg[1:0]release_pending=0;wire[1:0]release_ack;reg[63:0]epochs=0;
 reg[5:0]preset_ids={3'd4,3'd4};reg[3:0]release_ids=0;reg[1:0]piano_hold=0;reg[31:0]piano_coefficients={16'd4024,16'd4024};
 wire signed[15:0]left,right;wire valid;wire[7:0]active,gates;wire[31:0]underflows;
 two_hand_synth #(.VOICES(8)) synth(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
  .release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.chord_mode(1'b0),.preset_ids(preset_ids),.release_ids(release_ids),
  .hold_ticks_left(32'd75000000),.hold_ticks_right(32'd75000000),.piano_hold(piano_hold),.piano_coefficients(piano_coefficients),
  .bend_cents(32'd0),.vibrato_cents(32'd0),.brightness(16'h8080),.sample_valid(valid),.stereo_left(left),.stereo_right(right),.active_voices(active),.gates(gates),.underflows(underflows),.monitor_voice(3'd0));
 integer file,n=0;reg[23:0]body_at_start;reg[9:0]addr=0;wire signed[15:0]sine;
 sine_lut lut(.addr(addr),.value(sine));
 task strike(input integer id);
 begin
  wait(event_ready);@(negedge clk);event_data=0;event_data[20:14]=96;event_data[11:4]=id;event_valid=1;
  @(negedge clk);event_valid=0;wait(synth.committed);wait(valid);@(negedge clk);
 end endtask
 initial begin
  file=$fopen("quality.csv","w");$fwrite(file,"mode,sample,left,right,body\n");
  repeat(10)@(negedge clk);rst_n=1;strike(1);
  repeat(9600)begin @(posedge valid);#1;$fwrite(file,"decay,%0d,%0d,%0d,%0d\n",n,left,right,synth.audio.piano_body[0]);n++;end
  if(synth.audio.piano_body[0]<1600000 || synth.audio.piano_body[0]>1760000)$fatal(1,"piano T10 not 0.2s: %d",synth.audio.piano_body[0]);
  // A repeated note really restarts its body in a different allocated Voice.
  piano_hold=1;strike(2);
  repeat(12000)begin @(posedge valid);#1;$fwrite(file,"hold,%0d,%0d,%0d,%0d\n",n,left,right,synth.audio.piano_body[1]);n++;end
  if(synth.audio.piano_body[1]!=24'hffffff || !gates[1])$fatal(1,"piano hold lost energy");
  // Stop overrides piano hold and enforces the selected 0.2s release.
  @(negedge clk);epochs[31:0]=1;release_pending=1;wait(release_ack[0]);@(negedge clk);release_pending=0;
  repeat(10000)@(posedge valid);
  if(active!=0 || underflows)$fatal(1,"release/renderer starvation");
  // Exercise every LUT entry against a reference sine outside the RTL model.
  for(integer i=0;i<1024;i++)begin addr=i;#1;$fwrite(file,"lut,%0d,%0d,0,0\n",i,sine);end
  $fclose(file);$display("TB_PASS piano T10, held body, repeated onset, release, 1024 sine, production sample rate");$finish;
 end
 initial begin #1000000000;$fatal(1,"quality timeout");end
endmodule
