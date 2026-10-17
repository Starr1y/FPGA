`timescale 1ns/1ps
// Reuse the unchanged frozen 32-Voice regression with a passive PCM tap.
// The child bench retains its real oscillators, FX, DAC decoder and assertions.
module tb_synth_observer;
 tb_dual_synth #(.VOICES(32)) source_test();
 wire busy,frame_start,frame_done,bin_valid,bin_channel,wave_valid,wave_channel;
 wire[31:0]frame_id,dropped_blocks,completed_frames,last_cycles,max_cycles;
 wire[9:0]bin_index;wire signed[23:0]bin_real,bin_imag;
 wire[5:0]wave_column;wire signed[15:0]wave_min,wave_max;
 stereo_fft_observer observer(.clk(source_test.clk),.rst_n(source_test.rst_n),
  .pcm_valid(source_test.pcm_valid),.pcm_left(source_test.pcm_left),.pcm_right(source_test.pcm_right),
  .busy(busy),.frame_start(frame_start),.frame_done(frame_done),.frame_id(frame_id),
  .bin_valid(bin_valid),.bin_channel(bin_channel),.bin_index(bin_index),.bin_real(bin_real),.bin_imag(bin_imag),
  .wave_valid(wave_valid),.wave_channel(wave_channel),.wave_column(wave_column),.wave_min(wave_min),.wave_max(wave_max),
  .dropped_blocks(dropped_blocks),.completed_frames(completed_frames),.last_cycles(last_cycles),.max_cycles(max_cycles));
 integer fd,epoch=0;string result_file;
 initial begin
  if(!$value$plusargs("RESULT=%s",result_file))$fatal(1,"provide RESULT");
  fd=$fopen(result_file,"w");if(!fd)$fatal(1,"result file");
 end
 always @(negedge source_test.rst_n)epoch=epoch+1;
 always @(posedge source_test.clk)if(source_test.rst_n)begin
  if(source_test.pcm_valid)$fdisplay(fd,"P %0d %0d %0d",epoch,source_test.pcm_left,source_test.pcm_right);
  if(frame_start)$fdisplay(fd,"S %0d %0d",epoch,frame_id);
  if(wave_valid)$fdisplay(fd,"W %0d %0d %0d %0d %0d %0d",epoch,frame_id,wave_channel,wave_column,wave_min,wave_max);
  if(bin_valid)$fdisplay(fd,"B %0d %0d %0d %0d %0d %0d",epoch,frame_id,bin_channel,bin_index,bin_real,bin_imag);
  if(frame_done)begin
   if(dropped_blocks!=0)$fatal(1,"observer dropped at real audio cadence");
   $fdisplay(fd,"D %0d %0d %0d %0d %0d",epoch,frame_id,dropped_blocks,completed_frames,last_cycles);
  end
 end
 final $fclose(fd);
endmodule
