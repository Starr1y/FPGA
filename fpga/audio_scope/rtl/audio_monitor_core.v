// PCM -> real stereo FFT/waveform -> atomically adopted pixel-readable frame.
// This reusable component has no board pins or audio feedback/control outputs.
module audio_monitor_core(
 input core_clk,core_reset_n,input pcm_valid,input signed[15:0]pcm_left,pcm_right,
 input[31:0]active,owned,gates,input[223:0]notes,input[511:0]envelopes,
 output observer_busy,output[31:0]observer_drops,observer_frames,published_frames,skipped_frames,invalid_frames,
 input pixel_clk,pixel_reset_n,input frame_request,pixel_read_en,input[8:0]pixel_address,
 output[31:0]pixel_data,output pixel_frame_valid,output[31:0]pixel_frame_id,output pixel_updated
);
 wire frame_start,frame_done,bin_valid,bin_channel,wave_valid,wave_channel;
 wire[31:0]frame_id,last_cycles,max_cycles;wire[9:0]bin_index;
 wire signed[23:0]bin_real,bin_imag;wire[5:0]wave_column;wire signed[15:0]wave_min,wave_max;
 stereo_fft_observer observer(.clk(core_clk),.rst_n(core_reset_n),.pcm_valid(pcm_valid),.pcm_left(pcm_left),.pcm_right(pcm_right),
  .busy(observer_busy),.frame_start(frame_start),.frame_done(frame_done),.frame_id(frame_id),
  .bin_valid(bin_valid),.bin_channel(bin_channel),.bin_index(bin_index),.bin_real(bin_real),.bin_imag(bin_imag),
  .wave_valid(wave_valid),.wave_channel(wave_channel),.wave_column(wave_column),.wave_min(wave_min),.wave_max(wave_max),
  .dropped_blocks(observer_drops),.completed_frames(observer_frames),.last_cycles(last_cycles),.max_cycles(max_cycles));
 audio_observer_snapshot snapshot(.core_clk(core_clk),.core_reset_n(core_reset_n),.frame_start(frame_start),.frame_done(frame_done),.frame_id(frame_id),
  .bin_valid(bin_valid),.bin_channel(bin_channel),.bin_index(bin_index),.bin_real(bin_real),.bin_imag(bin_imag),
  .wave_valid(wave_valid),.wave_channel(wave_channel),.wave_column(wave_column),.wave_min(wave_min),.wave_max(wave_max),
  .active(active),.owned(owned),.gates(gates),.notes(notes),.envelopes(envelopes),.observer_cycles(last_cycles),.observer_drops(observer_drops),
  .published_frames(published_frames),.skipped_frames(skipped_frames),.invalid_frames(invalid_frames),
  .pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),.frame_request(frame_request),.pixel_read_en(pixel_read_en),.pixel_address(pixel_address),
  .pixel_data(pixel_data),.pixel_frame_valid(pixel_frame_valid),.pixel_frame_id(pixel_frame_id),.pixel_updated(pixel_updated));
endmodule
