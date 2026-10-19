`timescale 1ns/1ps
// Command/decoder boundary injection, not a real USB/IMU hardware claim.
module tb_ui21_stop;
 wire i2s_bck,i2s_ws,i2s_dout;
 reg clk=0;always #10 clk=~clk;
 reg reset_key=0,key0_n=1,key1_n=1,key2_n=1,pc_rx=1,encoder_a=1,encoder_b=1,encoder_button_n=1;
 tri1[1:0]imu_scl,imu_sda,imu_rst_n;reg[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,pc_tx,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 top_duo04 #(.BOOT_CYCLES(16)) dut(.*);
 initial begin
  repeat(30)@(negedge clk);force dut.running=1;@(negedge clk);release dut.running;
  force dut.cmd_done=1;force dut.cmd=61;force dut.cmd_len=1;force dut.cmd_data=512'd11;
  force dut.key_actions=12'h040;
  @(negedge clk);
  if(dut.running || dut.stop_reason!=3 || dut.response_code!=0)$fatal(1,"remote STOP did not bypass UI pipeline");
  release dut.cmd_done;release dut.cmd;release dut.cmd_len;release dut.cmd_data;release dut.key_actions;
  repeat(3)@(negedge clk);
  if(dut.running || dut.stop_reason!=3)$fatal(1,"STOP not applied");
  $display("TB_PASS global STOP priority over simultaneous local edit");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
