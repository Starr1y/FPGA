// Fail-closed IMU pad control. PGOOD must come from a real supply supervisor.
// No pad pull-ups are used: the sensor-side supply owns all external pull-ups.
module imu_io_guard #(
 parameter CLK_HZ=50000000, parameter QUALIFY_TICKS=CLK_HZ/100
)(input clk,input rst_n,input power_good,input fault_latched,input spi,
 input raw_tx,raw_cs_n,raw_mosi,raw_rst_n,raw_wake_n,
 output host_enable,output drive_enable,
 output tx,output cs_n,output mosi,output sensor_rst_n,output wake_n);
 reg [1:0] power_sync;
 reg qualified;
 reg [31:0] stable_ticks;
 // Loss of PGOOD clears qualification without waiting for a clock edge.
 wire guard_reset_n=power_good && rst_n;
 always @(posedge clk or negedge guard_reset_n)begin
  if(!guard_reset_n)begin power_sync<=0;qualified<=0;stable_ticks<=0;end
  else begin
   power_sync<={power_sync[0],1'b1};
   if(!power_sync[1])begin stable_ticks<=0;qualified<=0;end
   else if(!qualified)begin
    if(stable_ticks>=QUALIFY_TICKS-1)qualified<=1;
    else stable_ticks<=stable_ticks+1'b1;
   end
  end
 end
 assign host_enable=power_good && qualified && rst_n;
 assign drive_enable=host_enable && !fault_latched;
 assign tx=drive_enable && raw_tx ? 1'b0 : 1'bz;
 assign cs_n=1'bz;
 assign mosi=drive_enable && raw_mosi ? 1'b0 : 1'bz;
 assign wake_n=1'bz;
 // Open-drain reset; release voltage is provided by the module-side pull-up.
 assign sensor_rst_n=drive_enable && !raw_rst_n ? 1'b0 : 1'bz;
endmodule
