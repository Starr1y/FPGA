`timescale 1ns/1ps
// Decoded-command boundary test, not a UART or physical-board measurement.
module tb_io22_control_pipeline;
 reg[1:0]wrist_button_n=3;
 reg clk=0;always #10 clk=~clk;
 reg reset_key=0,key0_n=1,key1_n=1,key2_n=1,pc_rx=1;
 reg encoder_a=1,encoder_b=1,encoder_button_n=1;
 tri1[1:0]imu_scl,imu_sda,imu_rst_n;reg[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,pc_tx,i2s_bck,i2s_ws,i2s_dout;
 wire tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 top_duo04 #(.BOOT_CYCLES(16)) dut(.*);
 integer source_changes=0;
 always @(posedge clk)if(dut.rst_n && !dut.source_ready)begin
  source_changes<=source_changes+1;
  if(dut.event_valid || dut.host_ready || dut.sensor_ready)$fatal(1,"source transition consumed an event");
 end
 task command(input[7:0]op,input[6:0]len,input[511:0]payload);
 begin
  @(negedge clk);force dut.cmd_done=1;force dut.cmd=op;
  force dut.cmd_len=len;force dut.cmd_data=payload;
  @(negedge clk);release dut.cmd_done;release dut.cmd;release dut.cmd_len;release dut.cmd_data;
 end endtask
 task settle;repeat(6)@(negedge clk);endtask
 initial begin
  repeat(30)@(negedge clk);
  command(60,3,{488'b0,16'd128,8'd8});settle();
  if(dut.test_gain!=128)$fatal(1,"staged parameter edit lost");
  command(60,3,{488'b0,16'd300,8'd8});settle();
  if(dut.test_gain!=128 || dut.response_code!=2)$fatal(1,"invalid edit escaped validation");
  command(61,1,512'd6);settle();
  if(dut.presets[2:0]!=1)$fatal(1,"remote action/data did not remain paired");
  // Stop on the clock after a START edit was accepted, before it can apply.
  command(60,3,{488'b0,16'd1,8'd22});
  force dut.key_actions=12'h800;@(negedge clk);release dut.key_actions;settle();
  if(dut.running || dut.apply_local || dut.local_write)$fatal(1,"STOP replayed queued START");
  command(60,3,{488'b0,16'd1,8'd22});settle();
  if(!dut.running)$fatal(1,"ordinary START broken");
  command(60,3,{488'b0,16'd1,8'd0});settle();
  if(dut.running || !dut.use_host || dut.operating_mode!=1)$fatal(1,"source switch did not settle while stopped");
  command(60,3,{488'b0,16'd1,8'd22});settle();
  if(!dut.running)$fatal(1,"host START broken");
  command(61,1,512'd11);
  if(dut.running || dut.stop_reason!=3)$fatal(1,"remote STOP waited for menu pipeline");
  settle();if(dut.running)$fatal(1,"STOP did not remain stopped");
  command(60,3,{488'b0,16'd0,8'd0});settle();
  command(60,3,{488'b0,16'd1,8'd23});settle();
  force dut.sensor_valid=1;
  command(60,3,{488'b0,16'd1,8'd27});settle();release dut.sensor_valid;
  if(dut.operating_mode!=2 || !dut.use_host || source_changes<2)$fatal(1,"auto-start lesson source transition not covered");
  $display("TB_PASS control pipeline validation, remote data pairing, STOP flush/bypass, source transition backpressure incl auto-start lesson");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
