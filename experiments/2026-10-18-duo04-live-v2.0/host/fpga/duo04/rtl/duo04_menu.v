// Encoder navigation is separate from the authoritative parameter registers.
// Every edit is a semantic write, shared by UART and local controls.
module duo04_menu(input clk,rst_n,step,direction,short_press,long_press,
 input running,input[15:0]current_value,output reg[1:0]page,output reg[4:0]field,
 output reg editing,write,output reg[15:0]value);
 reg[15:0]minimum,maximum,increment;
 always @*begin
  minimum=0;maximum=1;increment=1;
  case(field)
   0:maximum=2;
   1,2:maximum=3;
   3,4:maximum=2;
   5,6:begin maximum=3;end
   8:begin maximum=256;increment=4;end
   9:maximum=3;
   10:begin maximum=255;increment=8;end
   11,12:begin minimum=100;maximum=10000;increment=100;end
   13,14:maximum=2;
   15,16:maximum=1;
   17,18:maximum=1;
   19:maximum=2;
   20:maximum=1;
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin page<=0;field<=0;editing<=0;write<=0;value<=0;end
  else begin
   write<=0;
   if(long_press)begin editing<=0;page<=0;field<=0;end
   else if(short_press)begin
    if(page==0)begin field<=22;value<=!running;write<=1;end
    else if(page==2)begin field<=20;value<=1;write<=1;end
    else if(page==3)begin field<=21;value<=1;write<=1;end
    else editing<=!editing;
   end else if(step)begin
    if(page==0)begin page<=direction ? 1 : 3;field<=0;end
    else if(!editing)begin
     if(page!=1)begin page<=direction ? (page==3 ? 0 : page+1'b1) : page-1'b1;field<=0;end
     else if(direction)begin if(field==19)begin page<=2;field<=19;end else field<=field+1'b1;end
     else if(field==0)begin page<=0;end else field<=field-1'b1;
    end else begin
     value<=direction ? (current_value>=maximum || current_value+increment>maximum ? maximum : current_value+increment) :
       (current_value<=minimum || current_value<minimum+increment ? minimum : current_value-increment);
     write<=1;
    end
   end
  end
 end
endmodule
