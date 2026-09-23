module frame_rx(input clk,input rst_n,input [7:0] din,input valid,
 output reg done,output reg [7:0] kind,output reg [15:0] seq,
 output reg [6:0] length,output reg [511:0] payload,output reg [31:0] errors);
 function [15:0] crc_next;
  input [15:0] c;input [7:0] d;integer j;reg [15:0] t;
  begin t=c^{d,8'b0};for(j=0;j<8;j=j+1)t=t[15]?(t<<1)^16'h1021:t<<1;crc_next=t;end
 endfunction
 reg active,magic_seen;reg [7:0] index;reg [15:0] crc;reg [7:0] crc_lo;reg [25:0] timeout;
 always @(posedge clk)begin
  if(!rst_n)begin active<=0;magic_seen<=0;index<=0;crc<=16'hffff;crc_lo<=0;timeout<=0;done<=0;kind<=0;seq<=0;length<=0;payload<=0;errors<=0;end
  else begin
   done<=0;
   if(valid)begin
    timeout<=0;
    if(!active)begin
     magic_seen<=din==8'ha5;
     if(magic_seen && din==8'h5a)begin active<=1;index<=0;crc<=16'hffff;length<=0;payload<=0;end
    end else begin
     index<=index+8'd1;
     if(index<10 || index<length+10)crc<=crc_next(crc,din);
     if(index==0 && din!=1 || index==2 && din>64 || index==3 && din!=0)begin active<=0;errors<=errors+1;end
     if(index==1)kind<=din;
     if(index==2)length<=din[6:0];
     if(index==4)seq[7:0]<=din;
     if(index==5)seq[15:8]<=din;
     if(index>=10 && index<length+10)payload[(index-10)*8+:8]<=din;
     if(index==length+10)crc_lo<=din;
     if(index==length+11)begin active<=0;magic_seen<=0;if({din,crc_lo}==crc)done<=1;else errors<=errors+1;end
    end
   end else if(active)begin
    if(timeout==25000000)begin active<=0;magic_seen<=0;errors<=errors+1;timeout<=0;end else timeout<=timeout+1;
   end
  end
 end
endmodule

module frame_tx(input clk,input rst_n,input start,input [7:0] kind,input [15:0] length,
 input [31:0] tick,output reg [15:0] addr,input [7:0] payload,
 output reg [7:0] data,output valid,input ready,output busy,output reg done);
 function [15:0] crc_next;
  input [15:0] c;input [7:0] d;integer j;reg [15:0] t;
  begin t=c^{d,8'b0};for(j=0;j<8;j=j+1)t=t[15]?(t<<1)^16'h1021:t<<1;crc_next=t;end
 endfunction
 reg [3:0] state;reg [3:0] pos;reg [15:0] seq,crc,n;reg [7:0] typ;reg [31:0] stamp;
 assign busy=state!=0;assign valid=state!=0 && state!=7;
 always @*begin
  data=0;
  case(state)
   1:data=8'ha5;2:data=8'h5a;
   3:case(pos)
    0:data=1;1:data=typ;2:data=n[7:0];3:data=n[15:8];4:data=seq[7:0];5:data=seq[15:8];
    6:data=stamp[7:0];7:data=stamp[15:8];8:data=stamp[23:16];9:data=stamp[31:24];
   endcase
   4:data=payload;5:data=crc[7:0];6:data=crc[15:8];
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin state<=0;pos<=0;seq<=0;addr<=0;done<=0;crc<=16'hffff;n<=0;typ<=0;stamp<=0;end
  else begin
   done<=0;
   if(state==0 && start)begin state<=1;n<=length;typ<=kind;stamp<=tick;addr<=0;crc<=16'hffff;end
   else if(state==7)begin state<=0;done<=1;seq<=seq+1;end
   else if(valid && ready)begin
    case(state)
     1:state<=2;
     2:begin state<=3;pos<=0;end
     3:begin crc<=crc_next(crc,data);if(pos==9)state<=n==0?5:4;else pos<=pos+1;end
     4:begin crc<=crc_next(crc,data);if(addr+1==n)state<=5;else addr<=addr+1;end
     5:state<=6;6:state<=7;
    endcase
   end
  end
 end
endmodule
