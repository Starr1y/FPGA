`timescale 1ns/1ps
// Command/decoder boundary injection, not a real USB/IMU hardware claim.
module tb_stable26_top;
 reg[1:0]wrist_button_n=3;
 wire i2s_bck,i2s_ws,i2s_dout;
 reg clk=0;always #10 clk=~clk;
 reg reset_key=0,key0_n=1,key1_n=1,key2_n=1,pc_rx=1,encoder_a=1,encoder_b=1,encoder_button_n=1;
 tri1[1:0]imu_scl,imu_sda,imu_rst_n;reg[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,pc_tx,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 top_duo04 #(.BOOT_CYCLES(16)) dut(.*);
 initial begin
  repeat(40)@(negedge clk);
  if(dut.status_bytes[7:0]!=10 || dut.status_bytes[3847:3840]!=1)$fatal(1,"diagnostic version");
  force dut.cmd_done=1;force dut.cmd=67;force dut.cmd_len=1;force dut.cmd_data=512'd1;
  @(negedge clk);release dut.cmd_done;release dut.cmd;release dut.cmd_len;release dut.cmd_data;
  repeat(4)@(negedge clk);
  if(!dut.output_mute || dut.status_bytes[3855:3848]!=1)$fatal(1,"mute command/readback");
  force dut.pcm_left=16'sd1234;force dut.pcm_right=-16'sd1234;
  #1;if(dut.dac.pcm_left!==16'sd0 || dut.dac.pcm_right!==16'sd0)$fatal(1,"DAC mute");
  if(dut.pcm_left!==16'sd1234)$fatal(1,"mute destroyed monitor");
  release dut.pcm_left;release dut.pcm_right;
  force dut.tx_busy=1;
  force dut.status_pending=0;@(negedge clk);release dut.status_pending;
  force dut.sensor_status=512'h0000000000000000000000000000000100000000000000000000000000000000;
  repeat(3)@(negedge clk);
  if(!dut.status_pending)$fatal(1,"hit count change did not request immediate status");
  release dut.sensor_status;
  force dut.status_timer=1249999;@(negedge clk);release dut.status_timer;
  @(negedge clk);if(dut.status_timer>1)$fatal(1,"25ms status cadence");
  force dut.use_host=0;force dut.sensor_status=512'h0000000000000000000000000000000200000000000000000000000000000000;
  repeat(4)@(negedge clk);
  if(dut.event_pending==0)$fatal(1,"compact event missing");
  force dut.response_pending=0;force dut.meta_pending=1;force dut.voice_meta_pending=1;force dut.tx_start=0;force dut.tx_done=0;
  force dut.tx_busy=0;@(negedge clk);
  if(dut.tx_kind!=140 || dut.tx_len!=32)$fatal(1,"event must precede sample/status");
  if(dut.saved_event[7:0]!=1 || dut.saved_event[95:64]!=2)$fatal(1,"event count/layout");
  release dut.sensor_status;
  $display("TB_PASS diagnostic layout / output-only mute / immediate hit notification / 25ms cadence");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule


