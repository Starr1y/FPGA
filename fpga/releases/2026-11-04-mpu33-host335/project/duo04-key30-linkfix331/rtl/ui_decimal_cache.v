// Five 16-bit UI numbers converted in16 pixel clocks during vertical blank.
// A new snapshot restarts the conversion; no partial result is published.
module ui_decimal_cache #(parameter COUNT=5)(
 input clk,rst_n,start,input[COUNT*16-1:0]values,
 output reg[COUNT*20-1:0]digits,output reg valid,busy
);
 reg[COUNT*16-1:0]binary;reg[COUNT*20-1:0]work_digits;
 reg[3:0]step;reg[COUNT*20-1:0]adjusted,next_digits;integer n,k;
 function[19:0]blanked;input[19:0]d;
 begin
  blanked=d;
  if(d[19:16]==0)blanked[19:16]=15;
  if(d[19:12]==0)blanked[15:12]=15;
  if(d[19:8]==0)blanked[11:8]=15;
  if(d[19:4]==0)blanked[7:4]=15;
 end endfunction
 always @*begin
  adjusted=work_digits;
  for(n=0;n<COUNT;n=n+1)begin
   for(k=0;k<5;k=k+1)if(work_digits[n*20+k*4+:4]>=5)adjusted[n*20+k*4+:4]=work_digits[n*20+k*4+:4]+4'd3;
   next_digits[n*20+:20]={adjusted[n*20+:19],binary[n*16+15]};
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin digits<={COUNT{20'hffff0}};binary<=0;work_digits<=0;step<=0;valid<=0;busy<=0;end
  else begin
   valid<=0;
   if(start)begin binary<=values;work_digits<=0;step<=15;busy<=1;end
   else if(busy)begin
    work_digits<=next_digits;
    for(integer j=0;j<COUNT;j=j+1)binary[j*16+:16]<=binary[j*16+:16]<<1;
    if(step==0)begin
     for(integer j=0;j<COUNT;j=j+1)digits[j*20+:20]<=blanked(next_digits[j*20+:20]);
     busy<=0;valid<=1;
    end else step<=step-1'b1;
   end
  end
 end
endmodule
