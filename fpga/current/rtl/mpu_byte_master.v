// Single-master open-drain I2C primitives. Commands: 0 START, 1 STOP,
// 2 WRITE, 3 READ+ACK, 4 READ+NACK. No output ever drives a logic one.
// HALF_DIV=100 at 50MHz: low >=2us, high >=2us (<=250kHz), Fast-mode
// minimum low 1.3us / high 0.6us. High time starts AFTER observed SCL rise.
module mpu_byte_master #(parameter HALF_DIV=100,parameter TIMEOUT=1250000,parameter HOLD_DIV=25)(
 input clk,rst_n,request,input [2:0] command,input [7:0] write_data,
 input scl_in,sda_in,output reg scl_low,output reg sda_low,
 output reg busy,done,ack,output reg [7:0] read_data,output reg [3:0] error
);
 reg [1:0] scl_sync,sda_sync;
 always @(posedge clk)begin scl_sync<={scl_sync[0],scl_in};sda_sync<={sda_sync[0],sda_in};end
 reg [3:0] state;reg [31:0] ticks,waiting;reg [2:0] op,bit_index;
 reg [7:0] shift;reg ack_bit;reg next_sda;reg[3:0] after_hold;
 localparam IDLE=0,START_WAIT=1,START_HOLD=2,STOP_LOW=3,STOP_RISE=4,STOP_HIGH=5,
 LOW=6,RISE=7,HIGH=8,ACK_LOW=9,ACK_RISE=10,ACK_HIGH=11,FINISH=12,DATA_HOLD=13;
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;scl_low<=0;sda_low<=0;busy<=0;done<=0;ack<=0;read_data<=0;error<=0;ticks<=0;waiting<=0;op<=0;shift<=0;bit_index<=7;ack_bit<=0;next_sda<=0;after_hold<=IDLE;end
  else begin
   done<=0;
   case(state)
    IDLE:if(request)begin
     busy<=1;error<=0;ack<=0;ticks<=0;waiting<=0;op<=command;bit_index<=7;shift<=write_data;
     if(command==0)begin scl_low<=0;sda_low<=0;state<=START_WAIT;end
     else if(command==1)begin scl_low<=1;sda_low<=1;state<=STOP_LOW;end
     else begin scl_low<=1;sda_low<=command==2 && !write_data[7];state<=LOW;end
    end
    START_WAIT:begin
     if(scl_sync[1] && sda_sync[1])begin
      if(ticks>=HALF_DIV-1)begin sda_low<=1;ticks<=0;state<=START_HOLD;end else ticks<=ticks+1;
     end else ticks<=0;
     if(waiting>=TIMEOUT-1)begin error<=14;state<=FINISH;scl_low<=0;sda_low<=0;end else waiting<=waiting+1;
    end
    START_HOLD:if(ticks>=HALF_DIV-1)begin scl_low<=1;next_sda<=sda_low;after_hold<=FINISH;ticks<=0;state<=DATA_HOLD;end else ticks<=ticks+1;
    STOP_LOW:if(ticks>=HALF_DIV-1)begin scl_low<=0;ticks<=0;waiting<=0;state<=STOP_RISE;end else ticks<=ticks+1;
    STOP_RISE:if(scl_sync[1])begin ticks<=0;state<=STOP_HIGH;end
     else if(waiting>=TIMEOUT-1)begin error<=13;sda_low<=0;state<=FINISH;end else waiting<=waiting+1;
    STOP_HIGH:if(ticks>=HALF_DIV-1)begin sda_low<=0;ticks<=0;state<=FINISH;end else ticks<=ticks+1;
    LOW:if(ticks>=HALF_DIV-1)begin scl_low<=0;ticks<=0;waiting<=0;state<=RISE;end else ticks<=ticks+1;
    RISE:if(scl_sync[1])begin ticks<=0;state<=HIGH;end
     else if(waiting>=TIMEOUT-1)begin error<=13;scl_low<=0;sda_low<=0;state<=FINISH;end else waiting<=waiting+1;
    HIGH:if(ticks>=HALF_DIV-1)begin
     if(op!=2)shift[bit_index]<=sda_sync[1];
     scl_low<=1;ticks<=0;
     if(bit_index==0)begin next_sda<=op==3;after_hold<=ACK_LOW;state<=DATA_HOLD;end
     else begin bit_index<=bit_index-1;next_sda<=op==2 && !shift[bit_index-1];after_hold<=LOW;state<=DATA_HOLD;end
    end else ticks<=ticks+1;
    ACK_LOW:if(ticks>=HALF_DIV-1)begin scl_low<=0;ticks<=0;waiting<=0;state<=ACK_RISE;end else ticks<=ticks+1;
    ACK_RISE:if(scl_sync[1])begin ticks<=0;state<=ACK_HIGH;end
     else if(waiting>=TIMEOUT-1)begin error<=13;scl_low<=0;sda_low<=0;state<=FINISH;end else waiting<=waiting+1;
    ACK_HIGH:if(ticks>=HALF_DIV-1)begin
     ack<=!sda_sync[1];read_data<=shift;scl_low<=1;next_sda<=0;ticks<=0;after_hold<=FINISH;state<=DATA_HOLD;
    end else ticks<=ticks+1;
    // Hold SDA after SCL falling: 25 core clocks = 500 ns at 50 MHz.
    // Then allow the full LOW interval for the next data setup.
    DATA_HOLD:if(ticks>=HOLD_DIV-1)begin sda_low<=next_sda;ticks<=0;state<=after_hold;end else ticks<=ticks+1;
    FINISH:begin done<=1;busy<=0;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
