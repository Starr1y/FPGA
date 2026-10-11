`timescale 1ns/1ps
module tb_i2c_guard;
 reg clk=0;always #10 clk=!clk;reg rst_n=0,power_good=0,fault_latched=0;
 reg raw_tx=0,raw_mosi=0,raw_rst_n=1;wire host_enable,drive_enable;
 tri tx,sda,rst;wire cs_n,wake_n;
 imu_io_guard #(.CLK_HZ(1000),.QUALIFY_TICKS(10)) dut(.clk(clk),.rst_n(rst_n),.power_good(power_good),.fault_latched(fault_latched),.spi(1'b1),
 .raw_tx(raw_tx),.raw_cs_n(1'b0),.raw_mosi(raw_mosi),.raw_rst_n(raw_rst_n),.raw_wake_n(1'b0),
 .host_enable(host_enable),.drive_enable(drive_enable),.tx(tx),.mosi(sda),.sensor_rst_n(rst),.cs_n(cs_n),.wake_n(wake_n));
 initial begin
  repeat(3)@(negedge clk);rst_n=1;raw_tx=1;raw_mosi=1;raw_rst_n=0;
  repeat(4)@(negedge clk);if(tx!==1'bz || sda!==1'bz || rst!==1'bz)$fatal(1,"disabled pads driven");
  power_good=1;wait(host_enable);@(negedge clk);
  if(tx!==0 || sda!==0 || rst!==0 || cs_n!==1'bz || wake_n!==1'bz)$fatal(1,"low requests/unused outputs wrong");
  raw_tx=0;raw_mosi=0;raw_rst_n=1;#1;if(tx!==1'bz || sda!==1'bz || rst!==1'bz)$fatal(1,"idle actively high");
  raw_tx=1;raw_mosi=1;raw_rst_n=0;fault_latched=1;#1;
  if(tx!==1'bz || sda!==1'bz || rst!==1'bz || drive_enable)$fatal(1,"fault not isolated");
  fault_latched=0;power_good=0;#1;if(host_enable || tx!==1'bz || sda!==1'bz || rst!==1'bz)$fatal(1,"disable not immediate");
  $display("TB_PASS I2C pad guard: disabled/fault/permission loss high-Z, idle high-Z, only low drive, unused SPI outputs high-Z");$finish;
 end
endmodule
