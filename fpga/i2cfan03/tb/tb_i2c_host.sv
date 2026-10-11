`timescale 1ns/1ps
module tb_i2c_host;
 reg clk=0;always #10 clk=!clk;reg rst_n=0,force_reset=0;
 tri1 scl,sda;wire sck,mosi,int_n,sensor_rst_n,configured;
 assign scl=sck ? 1'b0 : 1'bz;assign sda=mosi ? 1'b0 : 1'bz;
 wire online;wire [4:0] feature_mask;wire quat_valid,accel_valid,gyro_valid;
 wire [1:0] accuracy,accel_accuracy,gyro_accuracy;wire signed [15:0] qw,qz,az,gx;
 wire [31:0] protocol_errors,reset_attempts;wire address_ack;wire [15:0] received_packets;
 bno_i2c_host #(.RESET_TICKS(100),.BOOT_TICKS(100),.RESET_SETUP_TICKS(100),.HALF_DIV(100)) dut(
  .clk(clk),.rst_n(rst_n),.force_reset(force_reset),.miso(sda),.scl_in(scl),.int_n(int_n),.sck(sck),.mosi(mosi),
  .sensor_rst_n(sensor_rst_n),.online(online),.feature_mask(feature_mask),.protocol_errors(protocol_errors),
  .address_ack(address_ack),.received_packets(received_packets),.reset_attempts(reset_attempts),
  .quat_valid(quat_valid),.accel_valid(accel_valid),.gyro_valid(gyro_valid),.accuracy(accuracy),.accel_accuracy(accel_accuracy),.gyro_accuracy(gyro_accuracy),.qw(qw),.qz(qz),.az(az),.gx(gx));
 bno_i2c_sensor_model peer(.*);
 initial begin
  repeat(5)@(negedge clk);rst_n=1;peer.stretch_ns=17000;
  wait(configured);wait(feature_mask==31);
  if(online || protocol_errors || !address_ack || peer.commands!=11)$fatal(1,"configuration failed online=%b errors=%d ACK=%b cmds=%d",online,protocol_errors,address_ack,peer.commands);
  peer.accel_accuracy=1;peer.gyro_accuracy=2;
  peer.sensor_report(0,0,0,16384,2510,0);
  if(!online || qw!=16384 || az!=2510 || accuracy!=3)$fatal(1,"native report decode failed");
  if(accel_accuracy!=1 || gyro_accuracy!=2)$fatal(1,"independent raw quality bits were not retained");
  #55000000;if(online)$fatal(1,"stale acceleration remained online");
  peer.sensor_report(0,0,8192,14189,1486,512);
  if(!online || qz!=8192 || az!=1486 || gx!=512)$fatal(1,"stream recovery failed");
  if(peer.probes!=peer.transfers || received_packets!=peer.transfers)$fatal(1,"probe duplicated packet");
  @(negedge clk);force_reset=1;@(negedge clk);force_reset=0;wait(!sensor_rst_n);wait(configured);wait(feature_mask==31);
  if(online || protocol_errors || reset_attempts!=1)$fatal(1,"manual reset retained data");
  $display("TB_PASS I2C address4A, 17us stretch, continuation reads, native 12-byte 0x08 pose, five 100Hz features, independent Q/A/G quality, freshness/reset");$finish;
 end
 initial begin #180000000;$fatal(1,"host timeout mask=%h cmd=%d state=%d",feature_mask,peer.commands,dut.link.state);end
endmodule
