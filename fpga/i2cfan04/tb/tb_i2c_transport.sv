`timescale 1ns/1ps
module tb_i2c_transport;
 reg clk=0;always #10 clk=!clk;reg rst_n=0,tx_request=0;
 tri1 scl,sda;wire scl_low,sda_low,int_n,configured;reg sensor_rst_n=0;
 assign scl=scl_low ? 0 : 1'bz;assign sda=sda_low ? 0 : 1'bz;
 wire packet_ready;reg packet_take=0;wire [9:0] packet_length;reg [8:0] read_addr=0;wire [7:0] read_data;
 wire [31:0] errors;wire [15:0] received_bytes,received_packets,last_header;wire [3:0] transport_failure;wire address_ack,tx_done;
 shtp_i2c_link #(.CLK_HZ(1000000),.HALF_DIV(10),.STRETCH_TIMEOUT(1000)) dut(
  .clk(clk),.rst_n(rst_n),.enable(1'b1),.int_n(int_n),.miso(sda),.scl_in(scl),.scl_low(scl_low),.sda_low(sda_low),
  .tx_request(tx_request),.tx_length(8'd6),.tx_payload(168'hf900020006),.tx_done(tx_done),.address_ack(address_ack),
  .packet_ready(packet_ready),.packet_take(packet_take),.packet_length(packet_length),.read_addr(read_addr),.read_data(read_data),
  .errors(errors),.received_bytes(received_bytes),.received_packets(received_packets),.last_header(last_header),.transport_failure(transport_failure));
 bno_i2c_sensor_model peer(.*);
 task reset_link;begin rst_n=0;sensor_rst_n=0;repeat(5)@(negedge clk);rst_n=1;sensor_rst_n=1;end endtask
 reg [4095:0] p;integer i;
 initial begin
  reset_link();wait(packet_ready);if(packet_length!=5 || received_packets!=1 || received_bytes!=9)$fatal(1,"header probe/cargo wrong");
  @(negedge clk);packet_take=1;@(negedge clk);packet_take=0;wait(!packet_ready);
  // Largest supported cargo, containing inert channel0 payload.
  p=0;p[15:0]=512;for(i=4;i<512;i++)p[i*8+:8]=i[7:0];peer.enqueue(p);
  wait(packet_ready);if(packet_length!=512)$fatal(1,"512 boundary truncated");
  read_addr=511;#100;if(read_data!=8'hff)$fatal(1,"last byte lost");
  @(negedge clk);packet_take=1;@(negedge clk);packet_take=0;wait(!packet_ready);
  peer.corrupt_header=1;p=0;p[7:0]=5;peer.enqueue(p);wait(errors!=0);
  if(received_packets!=2 || last_header!=16'hffff || transport_failure!=3)$fatal(1,"FFFF published as valid");
  peer.corrupt_header=0;reset_link();peer.nack_address=1;wait(errors!=0);
  if(transport_failure!=12 || address_ack || packet_ready || received_bytes!=0)$fatal(1,"address NACK mishandled");
  peer.nack_address=0;reset_link();wait(packet_ready);@(negedge clk);packet_take=1;@(negedge clk);packet_take=0;wait(!packet_ready);
  peer.nack_payload=1;tx_request=1;wait(errors!=0);
  if(tx_done || transport_failure!=12)$fatal(1,"write NACK falsely acknowledged");
  tx_request=0;peer.nack_payload=0;peer.nack_cargo_once=1;reset_link();
  wait(packet_ready);
  if(received_packets!=1 || received_bytes!=9 || errors!=1 || peer.probes!=1 || peer.transfers!=1)
   $fatal(1,"cargo address NACK must retry same continuation, no extra probe/false packet");
  read_addr=1;#100;if(read_data!=0)$fatal(1,"continuation bit not normalized");
  read_addr=3;#100;if(read_data!=1)$fatal(1,"incremented continuation sequence lost");
  $display("TB_PASS I2C INT turnaround, continuation MSB/seq+1, same-cargo address NACK retry, 512-byte boundary, FFFF rejected, no false tx_done/PKT");$finish;
 end
 initial begin #12000000;$fatal(1,"transport timeout state=%d peerhead=%d tail=%d",dut.state,peer.head,peer.tail);end
endmodule
