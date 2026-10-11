// RETAINED_SPI_FAILURE_DIAGNOSTICS
// BNO08X native SHTP SPI, mode 3, MSB first. Default SCK=1MHz.
// INT is level-sensitive. One bounded packet is held until decoder acceptance.
module shtp_spi_link #(
 parameter CLK_HZ=50000000, parameter HALF_DIV=25, parameter WAIT_CS_ACK=0,
 parameter WAKE_TIMEOUT=CLK_HZ/20, parameter MAX_PACKET=512,
 parameter CS_SETUP_TICKS=(CLK_HZ/200000>0 ? CLK_HZ/200000 : 1),
 parameter CS_ACK_TIMEOUT=(CLK_HZ/1000>CS_SETUP_TICKS ? CLK_HZ/1000 : CS_SETUP_TICKS+1)
)(input clk,input rst_n,input enable,input int_n,input miso,
 output reg sck,output reg cs_n,output reg mosi,output reg wake_n,
 input tx_request,input [7:0] tx_length,input [167:0] tx_payload,
 output reg tx_done,output busy,
 output reg packet_ready,input packet_take,output reg [9:0] packet_length,
 input [8:0] read_addr,output [7:0] read_data,
 output reg [15:0] received_bytes,received_packets,
 output reg [31:0] errors,output reg startup_seen,output reg [15:0] last_header,
 output sampled_int_n,output sampled_miso,output reg [3:0] transport_failure);
 reg [7:0] mem[0:MAX_PACKET-1];assign read_data=mem[read_addr];
 reg [1:0] int_sync,miso_sync;
 reg [3:0] state;reg [31:0] timer;
 reg writing,bad_header;reg [167:0] outgoing;
 reg [15:0] position,total,rx_length;reg [7:0] out_length;
 reg [7:0] rx_shift,length_lsb;reg [2:0] bit_number;
 wire [7:0] byte_out=writing && position<out_length ? outgoing[position*8+:8] : 8'd0;
 assign busy=state!=0;
 assign sampled_int_n=int_sync[1];assign sampled_miso=miso_sync[1];
 localparam IDLE=0,WAKE=1,SETUP=2,FALL=3,RISE=4,BYTE=5,HOLD=6,GAP=7,SELECT=8;
 wire [15:0] header_length={rx_shift[7:0],length_lsb};
 always @(posedge clk)begin
  if(!rst_n)begin
   int_sync<=3;miso_sync<=3;state<=IDLE;timer<=0;
   sck<=1;cs_n<=1;mosi<=0;wake_n<=1;startup_seen<=0;
   tx_done<=0;packet_ready<=0;packet_length<=0;
   received_bytes<=0;received_packets<=0;errors<=0;last_header<=0;transport_failure<=0;
   writing<=0;bad_header<=0;outgoing<=0;position<=0;total<=4;
   rx_length<=0;out_length<=0;rx_shift<=0;length_lsb<=0;bit_number<=7;
  end else begin
   int_sync<={int_sync[0],int_n};miso_sync<={miso_sync[0],miso};tx_done<=0;
   if(!int_sync[1])startup_seen<=1;
   if(packet_take)packet_ready<=0;
   case(state)
    IDLE:begin
     sck<=1;cs_n<=1;wake_n<=1;mosi<=0;
     if(enable && !packet_ready)begin
      // Pending sensor cargo wins over a host command; never discard it.
      if(!int_sync[1])begin
       writing<=0;out_length<=0;total<=4;position<=0;rx_length<=0;
       bad_header<=0;cs_n<=0;bit_number<=7;rx_shift<=0;
       timer<=0;state<=SELECT;
      end else if(tx_request && startup_seen)begin
       writing<=1;outgoing<=tx_payload;out_length<=tx_length;total<=tx_length;
       position<=0;rx_length<=0;bad_header<=0;wake_n<=0;timer<=0;state<=WAKE;
      end
     end
    end
    WAKE:begin
     if(!int_sync[1])begin
      cs_n<=0;bit_number<=7;rx_shift<=0;timer<=0;state<=SELECT;
     end else if(timer>=WAKE_TIMEOUT-1)begin
      errors<=errors+1'b1;transport_failure<=2;wake_n<=1;timer<=HALF_DIV*2-1;state<=GAP;
      // No tx_done: host retries rather than treating an absent sensor as configured.
     end else timer<=timer+1'b1;
    end
    // Establish CS for 5 us, then clock like the proven TangLab bridge.
    // Optional INT-high waiting is for diagnostics only, disabled by default.
    SELECT:begin
     if(timer>=CS_SETUP_TICKS-1 && (!WAIT_CS_ACK || int_sync[1]))begin
      wake_n<=1;timer<=HALF_DIV-1;state<=SETUP;
     end else if(timer>=CS_ACK_TIMEOUT-1)begin
      cs_n<=1;sck<=1;wake_n<=1;errors<=errors+1'b1;transport_failure<=11;
      timer<=CLK_HZ/1000;state<=GAP;
     end else timer<=timer+1'b1;
    end
    SETUP:if(timer!=0)timer<=timer-1'b1;else state<=FALL;
    FALL:begin sck<=0;mosi<=byte_out[bit_number];timer<=HALF_DIV-1;state<=RISE;end
    RISE:if(timer!=0)timer<=timer-1'b1;else begin
     sck<=1;rx_shift[bit_number]<=miso_sync[1];timer<=HALF_DIV-1;
     if(bit_number==0)state<=BYTE;else begin bit_number<=bit_number-1'b1;state<=SETUP;end
    end
    BYTE:begin
     if(position<MAX_PACKET)mem[position[8:0]]<=rx_shift;
     if(received_bytes!=16'hffff)received_bytes<=received_bytes+1'b1;
     if(position==0)length_lsb<=rx_shift;
     if(position==1)begin
      if(!writing || header_length!=0)last_header<=header_length;
      // Reject unsupported continuations, failed-bus 0xffff and oversize cargo.
      // Never publish a truncated packet to the SH-2 decoder.
      if(header_length!=0 && (header_length[15] || header_length<4 || header_length>MAX_PACKET))begin
       bad_header<=1;errors<=errors+1'b1;transport_failure<=3;
      end else begin
       rx_length<=header_length;
       if(header_length>total)total<=header_length;
      end
     end
     if(position+1>=total)begin timer<=HALF_DIV-1;state<=HOLD;end
     else begin position<=position+1'b1;bit_number<=7;rx_shift<=0;state<=SETUP;end
    end
    HOLD:if(timer!=0)timer<=timer-1'b1;else begin
     cs_n<=1;sck<=1;wake_n<=1;mosi<=0;
     // Zero/4-byte header has no cargo (CEVA SPI HAL), never a pose packet.
     if(rx_length>4 && !bad_header)begin
      packet_ready<=1;packet_length<=rx_length[9:0];
      if(received_packets!=16'hffff)received_packets<=received_packets+1'b1;
     end
     // Invalid return data must not falsely acknowledge a host command.
     if(writing && !bad_header)tx_done<=1;
     timer<=bad_header ? CLK_HZ/1000 : HALF_DIV*2-1;state<=GAP;
    end
    GAP:if(timer!=0)timer<=timer-1'b1;else state<=IDLE;
    default:begin state<=IDLE;cs_n<=1;sck<=1;wake_n<=1;end
   endcase
  end
 end
endmodule
