// Linked stereo look-ahead limiter. The whole current sample is held while
// an integer divider finds a safe gain; never clip first and measure later.
// One input per >=40 core clocks; normal input period is about 1042 clocks.
module stereo_makeup_limiter #(parameter SHIFT=3,CEILING=28000)(
 input clk,rst_n,in_valid,input signed[15:0]in_left,in_right,
 output reg out_valid,output reg signed[15:0]out_left,out_right,
 output reg[31:0]dropped);
 reg[2:0]state;reg[5:0]remaining;
 wire signed[18:0]wide_left=$signed({{3{in_left[15]}},in_left})<<<SHIFT;
 wire signed[18:0]wide_right=$signed({{3{in_right[15]}},in_right})<<<SHIFT;
 wire[18:0]abs_left=wide_left[18] ? -wide_left : wide_left;
 wire[18:0]abs_right=wide_right[18] ? -wide_right : wide_right;
 wire[18:0]peak=abs_left>abs_right ? abs_left : abs_right;
 reg signed[18:0]held_left,held_right;reg signed[36:0]product_left,product_right;
 reg[31:0]numerator,quotient;reg[18:0]denominator;reg[19:0]remainder;
 wire[19:0]trial={remainder[18:0],numerator[31]};
 wire subtract=trial>={1'b0,denominator};
 wire[31:0]next_quotient={quotient[30:0],subtract};
 reg[16:0]desired,gain,applied;reg[11:0]peak_hold;
 wire[16:0]release_gain=gain>17'd65528 ? 17'd65536 : gain+17'd8;
 wire[16:0]next_gain=desired<gain ? desired : peak_hold!=0 ? gain : release_gain>desired ? desired : release_gain;
 wire signed[15:0]rounded_left=product_left[31:16]+{15'b0,(product_left[15] && (!product_left[36] || |product_left[14:0]))};
 wire signed[15:0]rounded_right=product_right[31:16]+{15'b0,(product_right[15] && (!product_right[36] || |product_right[14:0]))};
 always @(posedge clk)begin
  if(!rst_n)begin state<=0;out_valid<=0;out_left<=0;out_right<=0;dropped<=0;peak_hold<=0;gain<=65536;applied<=0;desired<=0;held_left<=0;held_right<=0;product_left<=0;product_right<=0;remaining<=0;numerator<=0;quotient<=0;denominator<=0;remainder<=0;end
  else begin
   out_valid<=0;if(in_valid && state!=0)dropped<=dropped+1'b1;
   case(state)
    0:if(in_valid)begin
     held_left<=wide_left;held_right<=wide_right;
     if(peak<=CEILING)begin desired<=65536;state<=2;end
     else begin numerator<=CEILING*65536;denominator<=peak;remainder<=0;quotient<=0;remaining<=32;state<=1;end
    end
    1:begin
     numerator<={numerator[30:0],1'b0};quotient<=next_quotient;
     remainder<=subtract ? trial-{1'b0,denominator} : trial;remaining<=remaining-1'b1;
     if(remaining==1)begin desired<=next_quotient[16:0];state<=2;end
    end
    2:begin
     if(desired<=gain && desired<65536)peak_hold<=2400;else if(peak_hold!=0)peak_hold<=peak_hold-1'b1;
     gain<=next_gain;applied<=next_gain;state<=3;end
    3:begin product_left<=held_left*$signed({1'b0,applied});product_right<=held_right*$signed({1'b0,applied});state<=4;end
    4:begin out_left<=rounded_left[15:0];out_right<=rounded_right[15:0];out_valid<=1;state<=0;end
   endcase
  end
 end
endmodule
