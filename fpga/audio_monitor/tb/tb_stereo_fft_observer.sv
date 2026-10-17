`timescale 1ns/1ps
module tb_stereo_fft_observer;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,pcm_valid=0;reg signed[15:0]pcm_left=0,pcm_right=0;
 wire busy,frame_start,frame_done,bin_valid,bin_channel,wave_valid,wave_channel;
 wire[31:0]frame_id,dropped_blocks,completed_frames,last_cycles,max_cycles;
 wire[9:0]bin_index;wire signed[23:0]bin_real,bin_imag;
 wire[5:0]wave_column;wire signed[15:0]wave_min,wave_max;
 stereo_fft_observer dut(.*);
 reg[31:0]vectors[0:9215];string data_file,result_file;integer fd,phase=0,done_count=0,start_count=0;
 integer n,k,step,global_sample=0;
 always @(posedge clk)begin
  if(rst_n)begin
   if(frame_start)begin start_count=start_count+1;$fdisplay(fd,"S %0d %0d",phase,frame_id);end
   if(wave_valid)$fdisplay(fd,"W %0d %0d %0d %0d %0d %0d",phase,frame_id,wave_channel,wave_column,wave_min,wave_max);
   if(bin_valid)$fdisplay(fd,"B %0d %0d %0d %0d %0d %0d",phase,frame_id,bin_channel,bin_index,bin_real,bin_imag);
   if(frame_done)begin
    done_count=done_count+1;
    if(last_cycles>=200000)$fatal(1,"observer processing exceeds 4 ms budget");
    $fdisplay(fd,"D %0d %0d %0d %0d %0d",phase,frame_id,dropped_blocks,completed_frames,last_cycles);
   end
  end
 end
 task reset_all;
  begin @(negedge clk);rst_n=0;pcm_valid=0;repeat(4)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);end
 endtask
 task send_block(input integer vector_id,input integer spacing);
  begin
   for(k=0;k<1024;k=k+1)begin
    @(negedge clk);{pcm_right,pcm_left}=vectors[vector_id*1024+k];pcm_valid=1;
    @(negedge clk);pcm_valid=0;
    step=spacing==0 ? (global_sample%3==2 ? 1041 : 1042) : spacing;
    global_sample=global_sample+1;
    repeat(step-2)@(negedge clk);
   end
  end
 endtask
 initial begin
  if(!$value$plusargs("DATA=%s",data_file) || !$value$plusargs("RESULT=%s",result_file))$fatal(1,"provide DATA and RESULT");
  $readmemh(data_file,vectors);fd=$fopen(result_file,"w");if(!fd)$fatal(1,"result file");
  reset_all();phase=1;
  for(n=0;n<9;n=n+1)send_block(n,0);
  wait(!busy);repeat(4)@(negedge clk);
  if(done_count!=9 || dropped_blocks!=0)$fatal(1,"native cadence dropped/corrupted frames");
  phase=2;reset_all();done_count=0;start_count=0;
  // Deliberately impossible 25 MHz sample cadence. Held capture bank must survive.
  for(n=0;n<6;n=n+1)send_block(n,2);
  wait(!busy);repeat(4)@(negedge clk);
  if(done_count!=1 || dropped_blocks!=5)$fatal(1,"overload must skip complete monitor blocks");
  send_block(7,0);wait(!busy);repeat(4)@(negedge clk);
  if(done_count!=2 || completed_frames!=2)$fatal(1,"overload recovery");
  phase=3;reset_all();done_count=0;start_count=0;
  send_block(6,2);repeat(1000)@(negedge clk);
  if(!busy)$fatal(1,"reset test not in flight");
  phase=4;reset_all();done_count=0;start_count=0;
  send_block(4,0);wait(!busy);repeat(4)@(negedge clk);
  if(done_count!=1 || start_count!=1 || completed_frames!=1 || dropped_blocks!=0)$fatal(1,"reset exposed stale transaction");
  $fclose(fd);$display("TB_PASS stereo FFT observer: 9 native stereo frames, overload/drop/recovery, reset abort, PCM not backpressured; max cycles %0d",max_cycles);$finish;
 end
 initial begin #400000000;$fatal(1,"watchdog");end
endmodule
