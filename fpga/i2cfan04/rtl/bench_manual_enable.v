// Manual operator permission ONLY: this is NOT a supply detector.
// Both keys: short 0.05-2 s/release changes the page; 2 s/release toggles permission.
// A chord consumes both keys until BOTH are released and stable for 20 ms.
module bench_manual_enable #(
 parameter CLK_HZ=50000000, HOLD_TICKS=CLK_HZ*2, RELEASE_TICKS=CLK_HZ/50,
 parameter SHORT_TICKS=CLK_HZ/20
)(input clk,input rst_n,input key1_n,input key2_n,
 output reg enabled=0,output filtered_key1_n,output filtered_key2_n,
 output reg view_toggle=0,output long_ready);
 reg [1:0] sync1=3,sync2=3;
 reg [31:0] held=0,released=0;
 reg ready=0,pending=0,blocked=1,short_pending=0;
 wire both_down=!sync1[1] && !sync2[1];
 wire both_up=sync1[1] && sync2[1];
 assign long_ready=pending;
 assign filtered_key1_n=blocked || both_down ? 1'b1 : sync1[1];
 assign filtered_key2_n=blocked || both_down ? 1'b1 : sync2[1];
 always @(posedge clk) begin
  if(!rst_n)begin
   sync1<=3;sync2<=3;enabled<=0;held<=0;released<=0;
   ready<=0;pending<=0;blocked<=1;short_pending<=0;view_toggle<=0;
  end else begin
   view_toggle<=0;
   sync1<={sync1[0],key1_n};sync2<={sync2[0],key2_n};
   if(both_up)begin
    held<=0;
    if(released<RELEASE_TICKS)released<=released+1;
    else begin
     ready<=1;blocked<=0;
     if(pending)begin enabled<=!enabled;pending<=0;short_pending<=0;end
     else if(short_pending)begin view_toggle<=1;short_pending<=0;end
    end
   end else begin
    released<=0;
    if(both_down)begin
     blocked<=1;
     if(ready && !pending)begin
      if(held<HOLD_TICKS)begin
       held<=held+1;
       if(held>=SHORT_TICKS-1)short_pending<=1;
      end else begin pending<=1;ready<=0;short_pending<=0;end
     end
    end else held<=0;
   end
  end
 end
endmodule
