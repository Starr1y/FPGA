// SPI compatibility: PS0 setup 10 ms, open-drain reset low 10 ms.
// RETAINED_SPI_FAILURE_DIAGNOSTICS
module bno_imu_host #(
    parameter REPORT_BACKPRESSURE=0,
    parameter SPI=0, parameter HALF_DIV=100, parameter CLK_HZ=50000000,
    parameter RESET_TICKS=CLK_HZ/100,
    parameter BOOT_TICKS=CLK_HZ*3/4,
    parameter QUERY_TIMEOUT=CLK_HZ/5,
    parameter RETRY_TICKS=CLK_HZ*3,
    parameter TX_SPACING=CLK_HZ/5000,
    parameter MAX_AUTO_RESETS=2, parameter RESET_SETUP_TICKS=CLK_HZ/100
)(
    input clk,input rst_n,input force_reset,input rx,input scl_in,input int_n,input linear_ready,
    output address_ack,output tx,output cs_n,output mosi,output wake_n,output sensor_rst_n,output fault_latched,
    output online,output [4:0] feature_mask,
    output [2:0] link_state,output [31:0] reset_attempts,
    output quat_valid,output signed [15:0] qx,qy,qz,qw,output [1:0] accuracy,accel_accuracy,gyro_accuracy,
    output [7:0] linear_sequence,output [31:0] linear_timestamp_ticks,output linear_timestamp_valid,
    output accel_valid,gyro_valid,gravity_valid,linear_valid,
    output signed [15:0] ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz,
    output [15:0] pose_hz,accel_hz,gyro_hz,
    output [31:0] protocol_errors,sequence_gaps,
    output sensor_restarted,
    output [15:0] received_bytes,received_packets,output [2:0] stream_fresh,
    output [3:0] first_failure_reason,output [3:0] failure_reason,output [15:0] failure_header,output [1:0] failure_inputs
);
 generate if(SPI)begin: spi
 bno_i2c_host #(.REPORT_BACKPRESSURE(REPORT_BACKPRESSURE),.CLK_HZ(CLK_HZ),.RESET_TICKS(RESET_TICKS),.BOOT_TICKS(BOOT_TICKS),
  .RETRY_TICKS(RETRY_TICKS),.HALF_DIV(HALF_DIV),.MAX_AUTO_RESETS(MAX_AUTO_RESETS),.RESET_SETUP_TICKS(RESET_SETUP_TICKS)) sensor(
 .miso(rx),.scl_in(scl_in),.address_ack(address_ack),.int_n(int_n),.sck(tx),.cs_n(cs_n),.mosi(mosi),.wake_n(wake_n),
 .clk(clk),.rst_n(rst_n),.force_reset(force_reset),.sensor_rst_n(sensor_rst_n),.fault_latched(fault_latched),
 .online(online),.feature_mask(feature_mask),.link_state(link_state),.reset_attempts(reset_attempts),
 .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.accel_accuracy(accel_accuracy),.gyro_accuracy(gyro_accuracy),
 .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),.linear_sequence(linear_sequence),
 .linear_timestamp_ticks(linear_timestamp_ticks),.linear_timestamp_valid(linear_timestamp_valid),
 .linear_ready(linear_ready),
 .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),
 .lx(lx),.ly(ly),.lz(lz),.pose_hz(pose_hz),.accel_hz(accel_hz),.gyro_hz(gyro_hz),
 .protocol_errors(protocol_errors),.sequence_gaps(sequence_gaps),.sensor_restarted(sensor_restarted),
 .received_bytes(received_bytes),.received_packets(received_packets),.stream_fresh(stream_fresh),
 .first_failure_reason(first_failure_reason),.failure_reason(failure_reason),.failure_header(failure_header),.failure_inputs(failure_inputs));
 end else begin: uart
 assign linear_sequence=0;
 assign linear_timestamp_ticks=0;assign linear_timestamp_valid=0;
 assign accel_accuracy=0;assign gyro_accuracy=0;assign address_ack=0;assign first_failure_reason=0;assign failure_reason=0;assign failure_header=0;assign failure_inputs=0;
 assign cs_n=1;assign mosi=0;assign wake_n=0;
 bno_uart_host #(.CLK_HZ(CLK_HZ),.RESET_TICKS(RESET_TICKS),.BOOT_TICKS(BOOT_TICKS),
 .QUERY_TIMEOUT(QUERY_TIMEOUT),.RETRY_TICKS(RETRY_TICKS),.TX_SPACING(TX_SPACING),.MAX_AUTO_RESETS(MAX_AUTO_RESETS)) sensor(.rx(rx),.tx(tx),
 .clk(clk),.rst_n(rst_n),.force_reset(force_reset),.sensor_rst_n(sensor_rst_n),.fault_latched(fault_latched),
 .online(online),.feature_mask(feature_mask),.link_state(link_state),.reset_attempts(reset_attempts),
 .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),
 .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),
 .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),
 .lx(lx),.ly(ly),.lz(lz),.pose_hz(pose_hz),.accel_hz(accel_hz),.gyro_hz(gyro_hz),
 .protocol_errors(protocol_errors),.sequence_gaps(sequence_gaps),.sensor_restarted(sensor_restarted),
 .received_bytes(received_bytes),.received_packets(received_packets),.stream_fresh(stream_fresh));
 end endgenerate
endmodule
