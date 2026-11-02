// Physical names match Dock silk: KEY1=Y12, KEY2=AB13 (legacy names were swapped).
// Actions happen on debounced release. Any two-key gesture consumes both singles.
module duo_key_events #(
 parameter CLK_HZ=50000000,DEBOUNCE_MS=20,SHORT_MS=50,
 parameter LONG_MS=1500,COMBO_MS=2000,EXPRESS_MS=300
)(input clk,rst_n,input key0_n,key1_n,key2_n,
 output reg[11:0]actions,output express_held,key1_pressed,output combo_active);
 reg[2:0]sync1,sync2,stable;
 reg[15:0]debounce[0:2],held[0:2];
 reg[31:0]divider;wire tick=divider==CLK_HZ/1000-1;
 reg blocked,long_combo,interrupted;reg[2:0]combo;reg[15:0]combo_ms;
 wire[2:0]pressed=~stable;
 wire pair=pressed==3'b011 || pressed==3'b101 || pressed==3'b110 || pressed==3'b111;
 assign combo_active=blocked || pair;
 assign express_held=!blocked && !pair && pressed==3'b010 && held[1]>=EXPRESS_MS;
 assign key1_pressed=pressed[1];
 reg armed;reg[1:0]sync_ready;reg[15:0]release_ms;
 integer i;
 always @(posedge clk) begin
  if(!rst_n)begin
   sync1<=7;sync2<=7;stable<=7;divider<=0;actions<=0;armed<=0;sync_ready<=0;release_ms<=0;
   blocked<=0;combo<=0;combo_ms<=0;long_combo<=0;interrupted<=0;
   for(i=0;i<3;i=i+1)begin debounce[i]<=0;held[i]<=0;end
  end else begin
   sync1<={key2_n,key1_n,key0_n};sync2<=sync1;sync_ready<={sync_ready[0],1'b1};actions<=0;
   divider<=tick ? 0 : divider+1'b1;
   if(tick)begin
    for(i=0;i<3;i=i+1)begin
     if(sync2[i]==stable[i])debounce[i]<=0;
     else if(debounce[i]>=DEBOUNCE_MS-1)begin stable[i]<=sync2[i];debounce[i]<=0;end
     else debounce[i]<=debounce[i]+1'b1;
    end
    // A key held across reset cannot enable a sensor on its later release.
    if(!armed)begin
     for(i=0;i<3;i=i+1)held[i]<=0;
     if(&sync_ready && sync2==7 && stable==7)begin
      if(release_ms>=DEBOUNCE_MS-1)armed<=1;else release_ms<=release_ms+1'b1;
     end else release_ms<=0;
    end else if(blocked)begin
     for(i=0;i<3;i=i+1)held[i]<=0;
     if(pressed==3'b111 && combo!=3'b111)begin
      // A slightly later third key upgrades the chord, consuming both singles.
      // The three-key hold starts here; time spent on a pair cannot qualify it.
      combo<=3'b111;combo_ms<=1;long_combo<=0;interrupted<=0;
     end else if(pressed==combo && !interrupted)begin
      if(combo_ms<COMBO_MS)combo_ms<=combo_ms+1'b1;
      if(combo_ms>=COMBO_MS-1)long_combo<=1;
     end else if(pressed!=0)begin
      // Preserve short duration through skewed release; do not resume a hold.
      interrupted<=1;
     end else begin
      if(long_combo)case(combo)
       3'b110:actions[5]<=1;
       3'b101:actions[7]<=1;
       3'b011:actions[8]<=1;
       3'b111:actions[9]<=1;
       default:begin end
      endcase
      else if(combo_ms>=SHORT_MS)begin
       if(combo==3'b110)actions[6]<=1;
       else if(combo==3'b011)actions[11]<=1;
       else if(combo==3'b111)actions[10]<=1;
      end
      blocked<=0;combo<=0;combo_ms<=0;long_combo<=0;interrupted<=0;
     end
    end else if(pair)begin
     blocked<=1;combo<=pressed;combo_ms<=1;long_combo<=0;interrupted<=0;
     for(i=0;i<3;i=i+1)held[i]<=0;
    end else begin
     for(i=0;i<3;i=i+1)begin
      if(pressed[i])begin if(held[i]<COMBO_MS)held[i]<=held[i]+1'b1;end
      else if(held[i]!=0)begin
       held[i]<=0;
       if(held[i]>=SHORT_MS)case(i)
        0:if(held[i]>=LONG_MS)begin
           actions[1]<=1;
          end else actions[0]<=1;
        1:if(held[i]<EXPRESS_MS)actions[2]<=1;
        2:if(held[i]>=LONG_MS)actions[4]<=1;else actions[3]<=1;
       endcase
      end
     end
    end
   end
  end
 end
endmodule
