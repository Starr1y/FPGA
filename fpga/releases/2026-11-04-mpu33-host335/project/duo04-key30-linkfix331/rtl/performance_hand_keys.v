// Per-hand active-low buttons. One-shot octave + explicit long-hold chord.
// Octave encoding: C3=3, C4=0, C5=1, matching dual_note_map.
module performance_hand_keys #(parameter CLK_HZ=50000000, DEBOUNCE_MS=10,LONG_MS=180)(
 input clk,rst_n,clear,consume,input[1:0]key_n,
 output reg[1:0]octave,output reg holding,output reg pending,
 output[1:0]pressed,output reg judging);
 reg[1:0]sync1,sync2,stable,armed,gesture_mask;
 reg[15:0]db0,db1,held_ms;reg[31:0]divider;
 reg long_seen;wire tick=divider==CLK_HZ/1000-1;
 assign pressed=~stable & armed;
 function[1:0]decode;input[1:0]mask;
 begin case(mask)1:decode=1;2:decode=3;default:decode=0;endcase end endfunction
 always @(posedge clk)begin
  if(!rst_n)begin sync1<=3;sync2<=3;stable<=3;armed<=0;db0<=0;db1<=0;held_ms<=0;divider<=0;octave<=0;holding<=0;pending<=0;judging<=0;long_seen<=0;gesture_mask<=0;end
  else begin
   sync1<=key_n;sync2<=sync1;
   if(tick)divider<=0;else divider<=divider+1'b1;
   if(clear)begin armed<=0;holding<=0;pending<=0;judging<=0;held_ms<=0;long_seen<=0;gesture_mask<=0;octave<=0;end
   else begin
    if(consume && !holding)begin pending<=0;octave<=0;end
    if(tick)begin
     if(sync2[0]==stable[0])db0<=0;else if(db0==DEBOUNCE_MS-1)begin stable[0]<=sync2[0];db0<=0;end else db0<=db0+1'b1;
     if(sync2[1]==stable[1])db1<=0;else if(db1==DEBOUNCE_MS-1)begin stable[1]<=sync2[1];db1<=0;end else db1<=db1+1'b1;
     if(stable[0] && sync2[0])armed[0]<=1;if(stable[1] && sync2[1])armed[1]<=1;
     if(pressed!=0)begin
      judging<=!long_seen;gesture_mask<=gesture_mask|pressed;
      if(held_ms<LONG_MS)held_ms<=held_ms+1'b1;
      if(held_ms>=LONG_MS-1)begin holding<=1;long_seen<=1;judging<=0;pending<=0;octave<=decode(pressed);end
     end else begin
      holding<=0;judging<=0;held_ms<=0;
      if(long_seen)begin octave<=0;pending<=0;end
      else if(gesture_mask!=0)begin octave<=decode(gesture_mask);pending<=gesture_mask!=3;end
      gesture_mask<=0;long_seen<=0;
     end
    end
   end
  end
 end
endmodule

