`timescale 1ns/1ps
// Inject semantic menu writes, not fake sensor packets. UART is tested separately.
module tb_duo04_modes;
 reg clk=0;always #10 clk=~clk;
 reg reset_key=0,key0_n=1,key1_n=1,key2_n=1,pc_rx=1;
 reg encoder_a=1,encoder_b=1,encoder_button_n=1;
 tri1[1:0]imu_scl,imu_sda,imu_rst_n;reg[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,pc_tx,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 top_duo04 #(.BOOT_CYCLES(16),.KEY_DEBOUNCE(8),.WATCHDOG_CYCLES(5000)) dut(.*);
 task edit(input[4:0]field,input[15:0]value);
 begin
  @(negedge clk);force dut.menu_field=field;force dut.menu_value=value;force dut.menu_write=1;
  @(negedge clk);release dut.menu_write;release dut.menu_field;release dut.menu_value;
  repeat(3)@(negedge clk);
 end endtask
 initial begin
  repeat(30)@(negedge clk);
  if(dut.running || dut.operating_mode!=0)$fatal(1,"startup");
  edit(22,1);repeat(12000)@(negedge clk);
  if(!dut.running)$fatal(1,"offline stopped on PC heartbeat timeout");
  // Inject decoder-boundary online/note events, not a fabricated I2C pass.
  force dut.sensors.online=2'b01;
  repeat(10)@(negedge clk);
  force dut.sensors.payload=64'h0000000000180010;
  force dut.sensors.note_on=2'b01;
  @(negedge clk);release dut.sensors.note_on;release dut.sensors.payload;
  repeat(2500)@(negedge clk);
  if(dut.gates[15:0]==0)$fatal(1,"sensor event mux failed");
  force dut.sensors.online=2'b00;repeat(2500)@(negedge clk);
  if(dut.gates[15:0]!=0)$fatal(1,"offline hand cancellation failed");
  release dut.sensors.online;
  edit(0,1);if(dut.running)$fatal(1,"mode switch not muted");
  edit(22,1);repeat(6000)@(negedge clk);
  if(dut.running || dut.stop_reason!=2)$fatal(1,"host timeout did not stop");
  edit(0,0);edit(22,1);
  key2_n=0;repeat(30)@(negedge clk);key2_n=1;repeat(30)@(negedge clk);
  if(dut.running || dut.stop_reason!=3)$fatal(1,"KEY2 not global stop");
  edit(20,1);if(dut.operating_mode!=2 || !dut.running)$fatal(1,"lesson start");
  repeat(6000)@(negedge clk);if(!dut.running)$fatal(1,"lesson requires PC heartbeat");
  edit(0,0);
  @(negedge clk);force dut.sine_enable=1;
  @(negedge clk);release dut.sine_enable;
  repeat(6000)@(negedge clk);
  if(dut.sine_enable || dut.stop_reason!=2)$fatal(1,"calibration lost watchdog outside mouse mode");
  $display("TB_PASS startup mute, mode-switch mute, offline/lesson no-PC, IMU event/disconnect boundary, host watchdog and KEY2");$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
