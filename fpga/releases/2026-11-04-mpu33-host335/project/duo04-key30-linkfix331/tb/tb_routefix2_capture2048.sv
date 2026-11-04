`timescale 1ns/1ps
module tb_routefix2_capture2048;
 reg[1:0]wrist_button_n=3;
 wire i2s_bck,i2s_ws,i2s_dout;
 reg clk=0;always #10 clk=~clk;
 reg encoder_a=1,encoder_b=1,encoder_button_n=1;
 reg reset_key=0,key0_n=1,key1_n=1,key2_n=1,pc_rx=1;
 tri[1:0]imu_scl,imu_sda,imu_rst_n;reg[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,pc_tx,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 // Packet gaps are shortened; sample rate, audio size, UART and FX RAM are production values.
 top_duo04 #(.BOOT_CYCLES(16),.KEY_DEBOUNCE(8),.CAPTURE_GAP_CYCLES(5000)) dut(.*);
 wire[7:0]byte_in;wire byte_valid;
 uart_rx listener(.clk(clk),.rst_n(dut.rst_n),.rx(pc_tx),.baud(32'd921600),.data(byte_in),.valid(byte_valid),.start(),.error());
 integer count=0;reg[143:0]expected[0:2047];
 always @(posedge dut.core_clk)if(dut.rst_n && dut.pcm_valid && (dut.cap_active || dut.begin_capture))begin
  if(count>=2048)$fatal(1,"capture overflow");
  expected[count]=dut.capture_word;count=count+1;
 end
 initial begin
  repeat(25)@(negedge clk);
  force dut.cmd=17;force dut.cmd_len=3;force dut.cmd_data=24'h080000;force dut.cmd_seq=1;force dut.cmd_done=1;
  @(negedge clk);release dut.cmd_done;release dut.cmd;release dut.cmd_len;release dut.cmd_data;release dut.cmd_seq;
  wait(dut.cap_ready);@(negedge clk);
  if(count!=2048 || dut.cap_points!=2048 || dut.cap_wr!=2047)$fatal(1,"capture count/last address");
  for(integer n=0;n<2048;n=n+1)if(dut.capture_mem[n]!==expected[n] || (^expected[n])===1'bx)$fatal(1,"unaligned sample %d",n);
  if(dut.cap_monitor_ids!==32'hffff1000 || dut.cap_monitor_count!=2)$fatal(1,"voice metadata");
  $display("TB_PASS 2048 complete ordered capture words, five buses and selected voices, no overflow; buffer-level test");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
