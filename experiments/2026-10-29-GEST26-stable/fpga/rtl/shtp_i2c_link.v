// BNO08X SHTP over I2C: read header (4 bytes), STOP, then read the entire
// transfer after INT reasserts. The continuation header sets bit15 and
// increments sequence (SHTP v1.10 section 2.3.1); it is not byte-identical.
// No register-pointer write and no register-style repeated START.
module shtp_i2c_link #(parameter CLK_HZ=50000000,parameter HALF_DIV=100,
 parameter STRETCH_TIMEOUT=CLK_HZ/40,parameter [6:0] ADDRESS=7'h4a)(
 input clk,rst_n,enable,int_n,miso,scl_in,output scl_low,sda_low,
 input tx_request,input [7:0] tx_length,input [167:0] tx_payload,
 output [31:0] timestamp_now,output reg tx_done,output busy,output reg startup_seen,address_ack,
 output reg packet_ready,input packet_take,output reg [9:0] packet_length,
 output reg [31:0] packet_hint_ticks,output reg packet_hint_valid,
 input [8:0] read_addr,output [7:0] read_data,
 output reg [31:0] errors,output reg [15:0] received_bytes,received_packets,last_header,
 output sampled_int_n,sampled_miso,output reg [3:0] transport_failure
);
 // SH-2 timebase is 100 us. Snapshot HINT for the initial header probe;
 // its later continuation interrupt and any NAK retry must not replace it.
 localparam TIME_DIV=CLK_HZ/10000;
 reg [1:0] int_sync;
 reg int_previous,hint_seen,read_hint_valid;
 reg [31:0] clock_ticks,time_divider,hint_ticks,read_hint_ticks;
 assign timestamp_now=clock_ticks;
 wire hint_edge=int_previous && !int_sync[1];
 always @(posedge clk)begin
  if(!rst_n || !enable)begin
   int_sync<=2'b11;int_previous<=1;clock_ticks<=0;time_divider<=0;hint_ticks<=0;hint_seen<=0;
  end else begin
   int_sync<={int_sync[0],int_n};int_previous<=int_sync[1];
   if(time_divider==TIME_DIV-1)begin time_divider<=0;clock_ticks<=clock_ticks+1'b1;end
   else time_divider<=time_divider+1'b1;
   if(hint_edge)begin hint_ticks<=clock_ticks;hint_seen<=1;end
  end
 end
 assign sampled_int_n=int_sync[1];assign sampled_miso=miso;
 reg [7:0] buffer[0:511];assign read_data=buffer[read_addr];
 reg [5:0] state;reg [1:0] phase;reg [9:0] index,length;
 reg [31:0] gap;reg [7:0] hdr[0:3];reg [167:0] payload;
 reg bad,continuation_seen,address_nak;reg [3:0] pending_error;
 reg [31:0] ready_wait;reg [1:0] read_retries;
 reg request;reg [2:0] command;reg [7:0] write_data;
 wire done,byte_busy,ack;wire [7:0] byte_data;wire [3:0] byte_error;
 i2c_byte_master #(.HALF_DIV(HALF_DIV),.TIMEOUT(STRETCH_TIMEOUT)) engine(
  .clk(clk),.rst_n(rst_n && enable),.request(request),.command(command),.write_data(write_data),
  .scl_in(scl_in),.sda_in(miso),.scl_low(scl_low),.sda_low(sda_low),
  .busy(byte_busy),.done(done),.ack(ack),.read_data(byte_data),.error(byte_error));
 localparam IDLE=0,START=1,START_WAIT=2,ADDR=3,ADDR_WAIT=4,DATA=5,DATA_WAIT=6,STOP=7,STOP_WAIT=8,COMPLETE=9,WAIT_CARGO=10;
 assign busy=state!=IDLE;
 wire [15:0] header_length={hdr[1],hdr[0]};
 always @(posedge clk)begin
  if(!rst_n || !enable)begin
   state<=IDLE;phase<=0;index<=0;length<=4;gap<=0;payload<=0;bad<=0;pending_error<=0;
   ready_wait<=0;read_retries<=0;continuation_seen<=0;address_nak<=0;
   request<=0;command<=0;write_data<=0;tx_done<=0;packet_ready<=0;packet_length<=0;
   packet_hint_ticks<=0;packet_hint_valid<=0;read_hint_ticks<=0;read_hint_valid<=0;
   errors<=0;received_bytes<=0;received_packets<=0;last_header<=0;transport_failure<=0;startup_seen<=0;address_ack<=0;
   hdr[0]<=0;hdr[1]<=0;hdr[2]<=0;hdr[3]<=0;
  end else begin
   request<=0;tx_done<=0;
   if(!int_sync[1])startup_seen<=1;
   if(packet_take)packet_ready<=0;
   case(state)
    IDLE:if(gap!=0)gap<=gap-1;
     else if(!packet_ready && !packet_take && !tx_done)begin
      bad<=0;pending_error<=0;index<=0;address_nak<=0;read_retries<=0;continuation_seen<=0;
      if(!int_sync[1])begin
       phase<=0;length<=4;state<=START;
       read_hint_ticks<=hint_edge ? clock_ticks : hint_ticks;
       read_hint_valid<=hint_seen || hint_edge;
      end
      else if(tx_request && tx_length>=4 && tx_length<=21)begin phase<=2;payload<=tx_payload;length<=tx_length;state<=START;end
     end
    WAIT_CARGO:begin
     // STOP-to-START pacing and a fresh ready interrupt are both needed.
     if(gap!=0)gap<=gap-1;
     else if(!int_sync[1])begin address_nak<=0;pending_error<=0;index<=0;bad<=0;continuation_seen<=0;state<=START;end
     if(ready_wait>=CLK_HZ/5)begin pending_error<=15;state<=COMPLETE;end
     else ready_wait<=ready_wait+1;
    end
    START:begin request<=1;command<=0;state<=START_WAIT;end
    START_WAIT:if(done)begin
     if(byte_error!=0)begin pending_error<=byte_error;state<=COMPLETE;end else state<=ADDR;
    end
    ADDR:begin request<=1;command<=2;write_data<={ADDRESS,phase!=2};state<=ADDR_WAIT;end
    ADDR_WAIT:if(done)begin
     if(byte_error!=0 || !ack)begin pending_error<=byte_error!=0 ? byte_error : 12;address_nak<=byte_error==0 && !ack;state<=STOP;end
     else begin address_ack<=1;state<=DATA;end
    end
    DATA:begin
     request<=1;command<=phase==2 ? 2 : index+1==length ? 4 : 3;
     write_data<=payload[index*8+:8];state<=DATA_WAIT;
    end
    DATA_WAIT:if(done)begin
     if(byte_error!=0 || phase==2 && !ack)begin pending_error<=byte_error!=0 ? byte_error : 12;state<=STOP;end
     else begin
      if(phase!=2)begin
       if(received_bytes!=16'hffff)received_bytes<=received_bytes+1;
       if(phase==0)hdr[index[1:0]]<=byte_data;
       else begin
        buffer[index[8:0]]<=index==1 ? byte_data & 8'h7f : byte_data;
        case(index)
         0:if(byte_data!=hdr[0])bad<=1;
         1:begin continuation_seen<=byte_data[7];if((byte_data & 8'h7f)!=hdr[1])bad<=1;end
         2:if(byte_data!=hdr[2])bad<=1;
         3:if(byte_data!=(continuation_seen ? hdr[3]+8'd1 : hdr[3]))bad<=1;
        endcase
       end
      end
      if(index+1==length)state<=STOP;else begin index<=index+1;state<=DATA;end
     end
    end
    STOP:begin request<=1;command<=1;state<=STOP_WAIT;end
    STOP_WAIT:if(done)begin if(byte_error!=0 && pending_error==0)pending_error<=byte_error;state<=COMPLETE;end
    COMPLETE:begin
     state<=IDLE;gap<=CLK_HZ/100000; // >=10us bus free / write pacing
     if(pending_error!=0)begin
      errors<=errors+1;gap<=CLK_HZ/100;
      if(transport_failure==0)transport_failure<=pending_error;
      // An address NAK consumed no cargo: retry that SAME continuation,
      // never launch a new four-byte probe into a half-read message.
      if(phase==1 && address_nak && read_retries<3)begin
       read_retries<=read_retries+1;ready_wait<=0;state<=WAIT_CARGO;
      end
     end else if(phase==2)tx_done<=1;
     else if(phase==0)begin
      last_header<=header_length;
      if(header_length==0 || header_length==4)begin end
      else if(header_length[15] || header_length<4 || header_length>512)begin
       errors<=errors+1;gap<=CLK_HZ/100;if(transport_failure==0)transport_failure<=3;
      end else begin phase<=1;length<=header_length[9:0];index<=0;ready_wait<=0;state<=WAIT_CARGO;end
     end else if(bad)begin errors<=errors+1;gap<=CLK_HZ/100;if(transport_failure==0)transport_failure<=3;end
     else begin
      packet_length<=length;packet_ready<=1;packet_hint_ticks<=read_hint_ticks;packet_hint_valid<=read_hint_valid;
      if(received_packets!=16'hffff)received_packets<=received_packets+1;
     end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
