// Active-low mechanical input; synchronize then debounce at a 1ms enable.
// Actions on release, no auto-repeat. A button held at reset/disable is ignored
// until a debounced release; plugging a held pedal in cannot change mode.
module release_button #(parameter DEBOUNCE_MS=20,SHORT_MS=50,LONG_MS=1500)(
 input clk,rst_n,tick_ms,enabled,input button_n,
 output reg short_release,long_release,pressed,output reg ready);
 reg sync1,sync2,stable;reg[1:0]sync_ready;reg[15:0]debounce,held;
 always @(posedge clk)begin
  if(!rst_n)begin sync1<=1;sync2<=1;sync_ready<=0;stable<=1;debounce<=0;held<=0;ready<=0;pressed<=0;short_release<=0;long_release<=0;end
  else begin
   sync1<=button_n;sync2<=sync1;sync_ready<={sync_ready[0],1'b1};short_release<=0;long_release<=0;
   if(!enabled)begin ready<=0;held<=0;pressed<=0;debounce<=0;stable<=sync2;end
   else if(tick_ms)begin
    if(sync2!=stable)begin
     if(debounce>=DEBOUNCE_MS-1)begin stable<=sync2;debounce<=0;end
     else debounce<=debounce+1'b1;
    end else debounce<=0;
    if(!ready)begin
     // Qualify an unpressed input, independently of synchronizer reset values.
     pressed<=0;held<=0;
     if(sync_ready[1] && sync2 && stable)begin
      if(held>=DEBOUNCE_MS-1)begin ready<=1;held<=0;end
      else held<=held+1'b1;
     end else held<=0;
    end else if(!stable)begin
     pressed<=1;if(held!=16'hffff)held<=held+1'b1;
    end else begin
     pressed<=0;held<=0;
     if(held>=LONG_MS)long_release<=1;
     else if(held>=SHORT_MS)short_release<=1;
    end
   end
  end
 end
endmodule
