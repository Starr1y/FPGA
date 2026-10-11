`timescale 1ns/1ps
module tb_ui_silent_top;
 reg clk=0;always #10 clk=!clk;
 reg key1_n=1,key2_n=1;tri1 imu_data,imu_clk_tx;
 wire hp_bck,hp_ws,hp_din,pa_en;
 top #(.BENCH_MANUAL(1),.AUTONOMOUS_SPI(1),.UI_ONLY(1),.BOOT_COUNTER_BITS(4)) dut(
 .clk(clk),.reset_key(1'b0),.key0_n(1'b1),.key1_n(key1_n),.key2_n(key2_n),
 .pc_rx(1'b1),.imu_data(imu_data),.imu_int_n(1'b1),.imu_power_good(1'b0),.imu_clk_tx(imu_clk_tx),
 .hp_bck(hp_bck),.hp_ws(hp_ws),.hp_din(hp_din),.pa_en(pa_en));
 // Only shorten human button timing in this integration fixture.
 defparam dut.manual.HOLD_TICKS=20,dut.manual.SHORT_TICKS=5,dut.manual.RELEASE_TICKS=3;
 integer sample_ticks=0,bck_edges=0;
 always @(posedge hp_bck)bck_edges++;
 always @(posedge clk)if(dut.rst_n)begin
  if(dut.sample_tick)sample_ticks++;
  #1;
  if(dut.samples!==80'd0 || dut.all_envelopes!==0 || dut.active_voices!==0 ||
     dut.sample_valid!==0 || dut.dac_left!==0 || dut.dac_right!==0 || hp_din!==0 || pa_en!==1)
    $fatal(1,"silent profile generated audio or enabled amplifier");
 end
 initial begin
  repeat(35)@(negedge clk);
  if(dut.diagnostic_view || dut.bench_enabled)$fatal(1,"startup defaults changed");
  key1_n=0;key2_n=0;repeat(12)@(negedge clk);key1_n=1;key2_n=1;repeat(12)@(negedge clk);
  if(!dut.diagnostic_view || dut.bench_enabled || !dut.performance_status[1003])
    $fatal(1,"short combo must switch diagnostics without enabling sensor");
  key1_n=0;key2_n=0;repeat(28)@(negedge clk);
  if(dut.bench_enabled || !dut.long_ready)$fatal(1,"long action must wait for release");
  key1_n=1;key2_n=1;repeat(12)@(negedge clk);
  if(!dut.bench_enabled || !dut.diagnostic_view)$fatal(1,"long combo toggled page or failed permission");
  repeat(20000)@(negedge clk);
  if(sample_ticks<10 || bck_edges<100)$fatal(1,"silent DAC timing generator stopped");
  $display("TB_PASS production silent top, DAC zeros, amplifier muted, key page/permission independent");$finish;
 end
 initial begin #2000000;$fatal(1,"silent top watchdog");end
endmodule
