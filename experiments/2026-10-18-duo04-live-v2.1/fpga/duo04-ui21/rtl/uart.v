module uart_rx #(parameter CLK_HZ=50000000)(
 input clk,input rst_n,input rx,input [31:0] baud,
 output reg [7:0] data,output reg valid,output reg start,output reg error);
 reg [1:0] sync;reg [31:0] count;reg [1:0] state;reg [2:0] bit_index;reg [7:0] shift;
 always @(posedge clk)begin
  if(!rst_n)begin sync<=3;state<=0;count<=0;valid<=0;start<=0;error<=0;shift<=0;data<=0;bit_index<=0;end
  else begin
   sync<={sync[0],rx};valid<=0;start<=0;error<=0;
   if(state==0)begin
    if(!sync[1])begin state<=1;count<=CLK_HZ/2;start<=1;end
   end else if(count<CLK_HZ-baud)count<=count+baud;
   else begin
    count<=count+baud-CLK_HZ;
    case(state)
     1:if(sync[1])state<=0;else begin state<=2;bit_index<=0;end
     2:begin shift<={sync[1],shift[7:1]};if(bit_index==7)state<=3;else bit_index<=bit_index+3'd1;end
     3:begin state<=0;if(sync[1])begin data<=shift;valid<=1;end else error<=1;end
     default:state<=0;
    endcase
   end
  end
 end
endmodule

module uart_tx #(parameter CLK_HZ=50000000)(
 input clk,input rst_n,input [31:0] baud,input [7:0] data,input valid,
 output ready,output reg tx);
 reg [31:0] count;reg [3:0] left;reg [9:0] shift;
 assign ready=(left==0);
 always @(posedge clk)begin
  if(!rst_n)begin tx<=1;left<=0;count<=0;shift<=1023;end
  else if(left==0)begin
   tx<=1;
   if(valid)begin shift<={1'b1,data,1'b0};tx<=0;left<=10;count<=0;end
  end else if(count<CLK_HZ-baud)count<=count+baud;
  else begin
   count<=count+baud-CLK_HZ;shift<={1'b1,shift[9:1]};tx<=shift[1];left<=left-1;
  end
 end
endmodule
