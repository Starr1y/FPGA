// Iterative unsigned square root and division, no combinational divider.
// Signed Q24 quaternion, result Q24. Reject degenerate input.
module imu_quaternion_normalize(input clk,rst_n,start,input[127:0]qin,
 output reg busy,valid,good,output reg[127:0]qout);
 reg signed[31:0]q[0:3];reg[63:0]norm,rad,rem,trial,dividend,quotient;
 reg[31:0]root,denom;reg[6:0]bitno;reg[2:0]state,index;
 wire signed[63:0]square=$signed(q[index[1:0]])*$signed(q[index[1:0]]);
 wire[63:0]sqrt_rem=(rem<<2)|{62'd0,rad[63:62]};
 wire[63:0]sqrt_trial=({32'd0,root}<<2)|64'd1;
 wire sqrt_take=sqrt_rem>=sqrt_trial;
 wire[63:0]div_rem=(rem<<1)|{63'd0,dividend[63]};
 wire div_take=div_rem>={32'd0,denom};
 wire[63:0]next_quotient={quotient[62:0],div_take};
 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;valid<=0;good<=0;qout<=0;norm<=0;rad<=0;rem<=0;trial<=0;dividend<=0;quotient<=0;root<=0;denom<=0;bitno<=0;state<=0;index<=0;for(i=0;i<4;i=i+1)q[i]<=0;end
  else begin
   valid<=0;
   case(state)
    0:if(start)begin for(i=0;i<4;i=i+1)q[i]<=$signed(qin[i*32+:32]);busy<=1;good<=0;norm<=0;index<=0;state<=1;end
    1:begin norm<=norm+$unsigned(square);if(index==3)state<=2;else index<=index+1'b1;end
    2:begin rad<=norm;root<=0;rem<=0;bitno<=31;state<=3;end
    3:begin
     rad<=rad<<2;rem<=sqrt_take ? sqrt_rem-sqrt_trial : sqrt_rem;root<={root[30:0],sqrt_take};
     if(bitno==0)begin denom<={root[30:0],sqrt_take};index<=0;state<=4;end else bitno<=bitno-1'b1;
    end
    4:if(denom<1024)begin good<=0;valid<=1;busy<=0;state<=0;end
      else begin dividend<=({32'd0,(q[index[1:0]]<0 ? -q[index[1:0]] : q[index[1:0]])}<<24);quotient<=0;rem<=0;bitno<=63;state<=5;end
    5:begin
     dividend<=dividend<<1;quotient<=next_quotient;rem<=div_take ? div_rem-denom : div_rem;
     if(bitno==0)begin qout[index*32+:32]<=q[index[1:0]]<0 ? -$signed(next_quotient[31:0]) : $signed(next_quotient[31:0]);
      if(index==3)begin good<=1;valid<=1;busy<=0;state<=0;end else begin index<=index+1'b1;state<=4;end
     end else bitno<=bitno-1'b1;
    end
    default:state<=0;
   endcase
  end
 end
endmodule
