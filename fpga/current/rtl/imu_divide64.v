// Unsigned64/32 restoring divider. One quotient bit per cycle.
module imu_divide64(input clk,rst_n,start,input[63:0]numerator,input[31:0]denominator,
 output reg busy,valid,good,output reg[63:0]quotient);
 reg[63:0]bits;reg[31:0]divisor,remainder;reg[5:0]index;
 wire[32:0]trial={remainder,bits[63]};
 wire take=trial>={1'b0,divisor};
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;valid<=0;good<=0;quotient<=0;bits<=0;divisor<=0;remainder<=0;index<=0;end
  else begin
   valid<=0;
   if(start&&!busy)begin
    quotient<=0;remainder<=0;bits<=numerator;divisor<=denominator;index<=63;
    good<=denominator!=0;busy<=denominator!=0;if(denominator==0)valid<=1;
   end else if(busy)begin
    bits<=bits<<1;quotient<={quotient[62:0],take};
    remainder<=take ? trial-{1'b0,divisor} : trial[31:0];
    if(index==0)begin busy<=0;valid<=1;end else index<=index-1'b1;
   end
  end
 end
endmodule
