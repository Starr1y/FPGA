// MPU register access sequencer. Byte-engine boundary is explicit for testing.
// Read uses repeated START without an intermediate STOP; last byte is NACKed. Data is MSB first.
module mpu_register_transaction(
 input clk,rst_n,start,read,input[6:0]device_address,
 input[7:0]register_address,write_value,input[4:0]read_count,
 output reg busy,done,output reg[3:0]failure,output reg[119:0]read_bytes,
 output reg request,output reg[2:0]command,output reg[7:0]write_data,
 input engine_done,engine_ack,input[3:0]engine_error,input[7:0]engine_data
);
 reg[3:0]step;reg waiting;reg reading;reg[6:0]address;
 reg[7:0]reg_addr,value;reg[4:0]count,index;
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;done<=0;failure<=0;read_bytes<=0;request<=0;command<=0;write_data<=0;step<=0;waiting<=0;reading<=0;address<=0;reg_addr<=0;value<=0;count<=0;index<=0;end
  else begin
   request<=0;done<=0;
   if(!busy)begin
    if(start)begin
     if(read && (read_count==0 || read_count>15))begin failure<=4;done<=1;end
     else begin busy<=1;failure<=0;read_bytes<=0;step<=0;waiting<=0;reading<=read;address<=device_address;reg_addr<=register_address;value<=write_value;count<=read_count;index<=0;end
    end
   end else if(!waiting)begin
    request<=1;waiting<=1;
    case(step)
     0,5:command<=0;
     1:begin command<=2;write_data<={address,1'b0};end
     2:begin command<=2;write_data<=reg_addr;end
     3:begin command<=2;write_data<=value;end
     4,8:command<=1;
     6:begin command<=2;write_data<={address,1'b1};end
     7:command<=index==count-1 ? 4 : 3;
     default:command<=1;
    endcase
   end else if(engine_done)begin
    waiting<=0;
    if(engine_error!=0)begin
     // Engine releases both lines on timeout. Do not start another transaction
     // on a failed bus until the caller has applied its recovery delay.
     failure<=engine_error;busy<=0;done<=1;
    end else if(command==2 && !engine_ack)begin
     failure<=1;step<=8; // Always issue STOP after an address/data NACK.
    end else case(step)
     0:step<=1;
     1:step<=2;
     2:step<=reading ? 5 : 3;
     3:step<=4;
     4:if(reading)step<=5;else begin busy<=0;done<=1;end
     5:step<=6;
     6:step<=7;
     7:begin
      read_bytes[index*8+:8]<=engine_data;
      if(index==count-1)step<=8;else index<=index+1'b1;
     end
     8:begin busy<=0;done<=1;end
     default:begin failure<=15;busy<=0;done<=1;end
    endcase
   end
  end
 end
endmodule
