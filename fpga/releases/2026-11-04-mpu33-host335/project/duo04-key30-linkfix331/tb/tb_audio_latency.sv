`timescale 1ns/1ps
module tb_audio_latency;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;
 wire sample_tick;reg event_valid=0;wire event_ready;reg[63:0]event_data=0;
 wire[1:0]release_ack;wire[31:0]underflows;wire[15:0]max_render;
 wire signed[15:0]dry_left,dry_right,pcm_left,pcm_right;wire sample_valid,pcm_valid;
 wire bck,ws,dout,i2s_bck,i2s_ws,i2s_dout;wire[31:0]fx_drops;wire[8:0]master_gain;
 two_hand_synth #(.VOICES(32),.ENABLE_EXPRESSION(1)) synth(
 .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
 .release_pending(2'b0),.release_ack(release_ack),.epochs(64'b0),.chord_mode(1'b0),.preset_ids(6'b0),.release_ids(4'b0),
 .hold_samples_left(32'd72000),.hold_samples_right(32'd72000),.piano_hold(2'b11),.piano_coefficients({16'd134,16'd134}),
 .bend_cents(32'b0),.vibrato_cents(32'b0),.brightness(16'h8080),.glide_coefficients(48'b0),.vibrato_ratios({20'd65536,20'd65536}),
 .underflows(underflows),.sample_valid(sample_valid),.max_render_cycles(max_render),.monitor_voice(5'd0),.stereo_left(dry_left),.stereo_right(dry_right));
 stereo_output_path #(.MAKEUP_SHIFT(3)) fx(.clk(clk),.rst_n(rst_n),.in_valid(sample_valid),.in_left(dry_left),.in_right(dry_right),
 .muted(1'b0),.test_gain(9'd8),.requested_mode(2'b0),.requested_wet(8'b0),.clear_history(2'b0),
 .pcm_left(pcm_left),.pcm_right(pcm_right),.pcm_valid(pcm_valid),.master_gain(master_gain),.fx_drops(fx_drops));
 stereo_serial_output serial(.*);
 realtime event_time=0,pcm_time=0,serial_time=0;
 always @(posedge pcm_valid)if(event_time!=0 && pcm_time==0 && (pcm_left!=0 || pcm_right!=0))pcm_time=$realtime;
 // First sampled nonzero serial bit is a digital boundary, not an analog measurement.
 always @(posedge i2s_bck)if(event_time!=0 && pcm_time!=0 && serial_time==0 && i2s_dout)serial_time=$realtime;
 initial begin
  repeat(10)@(negedge clk);rst_n=1;
  wait(master_gain==8);wait(event_ready);
  @(negedge clk);event_valid=1;event_data[11:4]=1;event_data[20:14]=96;event_data[28:25]=3;event_time=$realtime;
  @(negedge clk);event_valid=0;
  wait(serial_time!=0);#1000;
  if(underflows || fx_drops || serial_time-event_time>1000000)$fatal(1,"audio delay/drop");
  $display("TB_PASS actual32 synth + production FX/limiter/gain8 + serial; note acceptance-to-nonzero PCM=%0.3fus serial=%0.3fus render=%0d clocks",(pcm_time-event_time)/1000,(serial_time-event_time)/1000,max_render);$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
