// Atomic MPU register transaction. Each hand owns its bus (AD0=0, address68).
// Repeated START for reads; final byte NACK; open-drain master handles stretching.
module mpu6050_registers #(parameter HALF_DIV=100,TIMEOUT=1250000)(
 input clk,rst_n,start,read_op,input[6:0]address,input[7:0]register_address,write_value,
 input[4:0]read_count,input scl_in,sda_in,
 output scl_low,sda_low,output reg busy,done,output reg[3:0]error,
 output reg[111:0]data
);
 reg request;reg[2:0]command;reg[7:0]write_data;
 wire byte_busy,byte_done,ack;wire[7:0]received;wire[3:0]byte_error;
 reg reading,waiting;reg[6:0]addr;reg[7:0]reg_addr,value;
 reg[3:0]step;reg[4:0]count,index;
 i2c_byte_master #(.HALF_DIV(HALF_DIV),.TIMEOUT(TIMEOUT)) master(
 .clk(clk),.rst_n(rst_n),.request(request),.command(command),.write_data(write_data),
 .scl_in(scl_in),.sda_in(sda_in),.scl_low(scl_low),.sda_low(sda_low),
 .busy(byte_busy),.done(byte_done),.ack(ack),.read_data(received),.error(byte_error));
 always @(posedge clk)begin
  if(!rst_n)begin request<=0;command<=0;write_data<=0;busy<=0;done<=0;error<=0;data<=0;waiting<=0;step<=0;index<=0;count<=0;reading<=0;addr<=0;reg_addr<=0;value<=0;end
  else begin
   request<=0;done<=0;
   if(!busy && start)begin
    addr<=address;reg_addr<=register_address;value<=write_value;reading<=read_op;
    count<=read_count;index<=0;step<=0;waiting<=0;error<=0;data<=0;
    if(read_op && (read_count==0 || read_count>14))begin error<=4;done<=1;end else busy<=1;
   end else if(busy)begin
    if(!waiting && !byte_busy)begin
     waiting<=1;request<=1;
     case(step)
      0,3:begin command<=reading || step==0 ? 0 : 2;write_data<=value;end
      1:begin command<=2;write_data<={addr,1'b0};end
      2:begin command<=2;write_data<=reg_addr;end
      4:begin command<=reading ? 2 : 1;write_data<={addr,1'b1};end
      5:begin command<=index==count-1 ? 4 : 3;write_data<=0;end
      default:begin command<=1;write_data<=0;end
     endcase
    end else if(waiting && byte_done)begin
     waiting<=0;
     if(step==6 || (!reading && step==4))begin
      if(byte_error!=0)error<=byte_error;
      busy<=0;done<=1;
     end else if(byte_error!=0 || ((step==1 || step==2 || step==4 || (!reading && step==3)) && !ack))begin
      error<=byte_error!=0 ? byte_error : 4'd2;step<=6;
     end else if(reading && step==5)begin
      data[index*8+:8]<=received;
      if(index==count-1)step<=6;else index<=index+1'b1;
     end else step<=step+1'b1;
    end
   end
  end
 end
endmodule
