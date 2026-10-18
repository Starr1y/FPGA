`timescale 1ns/1ps
module tb_expression_quality;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,sample_tick=0,config_valid=0;reg[127:0]config_data=0;
 wire config_ready,valid;wire signed[15:0]left,right;wire[63:0]voice_samples;wire[3:0]active;wire[31:0]underflows;
 reg[47:0]glide_coefficients=0;wire[39:0]ratios;reg[63:0]rate_words={32'd492132,32'd492132};reg[15:0]depth_cents=0;
 reg[31:0]midi[0:127];initial $readmemh("rtl/midi_ftw.hex",midi);
 performance_vibrato lfo(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.rate_words(rate_words),.depth_cents(depth_cents),.ratios(ratios));
 dual_audio_core #(.VOICES(4),.ENABLE_EXPRESSION(1)) dut(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.config_valid(config_valid),.config_data(config_data),.config_ready(config_ready),
  .local_brightness(32'h80808080),.sample_valid(valid),.stereo_left(left),.stereo_right(right),.voice_samples(voice_samples),.active_voices(active),.underflows(underflows),
  .piano_hold(2'b11),.piano_coefficients({16'd134,16'd134}),.glide_coefficients(glide_coefficients),.vibrato_ratios(ratios),.monitor_voice(2'b0));
 integer count=0,file,k,note;
 always @(posedge clk)begin sample_tick<=0;if(rst_n)begin if(count==127)begin count<=0;sample_tick<=1;end else count<=count+1;end end
 task cfg(input integer index,frequency,preset,gate);
 begin wait(config_ready);@(negedge clk);config_data=0;config_data[7:0]=index;config_data[39:8]=frequency;config_data[47:40]=64;
  config_data[55]=1;config_data[56]=gate;config_data[58]=gate;config_data[59]=!gate;config_data[60]=preset>>2;config_data[51:50]=preset;
  config_data[79:64]=1024;config_data[95:80]=0;config_data[111:96]=65535;config_data[127:112]=47;config_valid=1;
  @(negedge clk);config_valid=0;end
 endtask
 task stop_all;
 begin for(integer j=0;j<4;j++)cfg(j,0,4,0);repeat(300)@(posedge valid);end
 endtask
 initial begin
  file=$fopen("expression.csv","w");$fwrite(file,"mode,index,value,freq,ratio\n");repeat(5)@(negedge clk);rst_n=1;
  for(note=36;note<=60;note+=12)begin
   stop_all();cfg(0,midi[note],4,1);repeat(18000)@(posedge valid);
   for(k=0;k<4096;k++)begin @(posedge valid);#1;$fwrite(file,"piano%d,%d,%d,%d,%d\n",note,k,$signed(voice_samples[15:0]),dut.v_freq,ratios[19:0]);end
  end
  stop_all();cfg(0,midi[60],5,1);repeat(100)@(posedge valid);glide_coefficients[23:0]=1748;cfg(1,midi[72],5,1);
  for(k=0;k<10000;k++)begin @(posedge valid);#1;if(k%32==0)$fwrite(file,"glide,%d,%d,%d,%d\n",k,dut.freq[1],midi[72],ratios[19:0]);end
  if(dut.freq[1]!=midi[72])$fatal(1,"glide never arrived");
  // Disable glide: a new note immediately uses exact target pitch.
  glide_coefficients=0;cfg(0,midi[48],5,1);repeat(2)@(posedge valid);
  if(dut.freq[0]!=midi[48])$fatal(1,"disabled glide changed pitch");
  depth_cents=40;
  for(k=0;k<48000;k++)begin @(posedge valid);#1;if(k%16==0)$fwrite(file,"vibrato,%d,%d,%d,%d\n",k,dut.phase[0],midi[48],ratios[19:0]);end
  depth_cents=0;repeat(5)@(posedge valid);if(ratios!={20'd65536,20'd65536})$fatal(1,"disabled vibrato not unity");
  stop_all();if(active || underflows)$fatal(1,"stop or renderer starvation");
  $fclose(file);$display("TB_PASS C2/C3/C4 piano, bounded glide arrival/off, vibrato/off, stop");$finish;
 end
 initial begin #300000000;$fatal(1,"timeout");end
endmodule
