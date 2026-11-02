// Physical names match Dock silk: KEY1=Y12, KEY2=AB13 (legacy names were swapped).
// Actions happen on debounced release. Any two-key gesture consumes both singles.
module duo_keys #(
 parameter CLK_HZ=50000000,DEBOUNCE_MS=20,SHORT_MS=50,
 parameter LONG_MS=1500,COMBO_MS=2000,EXPRESS_MS=300
)(input clk,rst_n,input key0_n,key1_n,key2_n,
 output reg focus,diagnostic,muted,chord_mode,
 output reg[1:0]enabled,calibrate,force_reset,
 output reg[3:0]profiles,presets,output reg[1:0]effect_mode,output reg[7:0]effect_wet,
 output[1:0]express,output combo_active);
 reg[2:0]sync1,sync2,stable;
 reg[15:0]debounce[0:2],held[0:2];
 reg[31:0]divider;wire tick=divider==CLK_HZ/1000-1;
 reg blocked,long_combo,interrupted;reg[2:0]combo;reg[15:0]combo_ms;
 wire[2:0]pressed=~stable;
 wire pair=pressed==3'b011 || pressed==3'b101 || pressed==3'b110 || pressed==3'b111;
 assign combo_active=blocked || pair;
 assign express=(!blocked && !pair && pressed==3'b010 && held[1]>=EXPRESS_MS && enabled[focus]) ? (focus ? 2'b10 : 2'b01) : 0;
 integer i;
 always @(posedge clk) begin
  if(!rst_n)begin
   sync1<=7;sync2<=7;stable<=7;divider<=0;focus<=0;diagnostic<=0;muted<=1;chord_mode<=0;
   enabled<=0;calibrate<=0;force_reset<=0;profiles<=0;presets<=0;effect_mode<=0;effect_wet<=128;blocked<=0;combo<=0;combo_ms<=0;long_combo<=0;interrupted<=0;
   for(i=0;i<3;i=i+1)begin debounce[i]<=0;held[i]<=0;end
  end else begin
   sync1<={key2_n,key1_n,key0_n};sync2<=sync1;calibrate<=0;force_reset<=0;
   divider<=tick ? 0 : divider+1'b1;
   if(tick)begin
    for(i=0;i<3;i=i+1)begin
     if(sync2[i]==stable[i])debounce[i]<=0;
     else if(debounce[i]>=DEBOUNCE_MS-1)begin stable[i]<=sync2[i];debounce[i]<=0;end
     else debounce[i]<=debounce[i]+1'b1;
    end
    if(blocked)begin
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
       3'b110:enabled[focus]<=!enabled[focus];
       3'b101:muted<=!muted;
       3'b011:chord_mode<=!chord_mode;
       3'b111:effect_mode<=effect_mode+1'b1;
       default:begin end
      endcase
      else if(combo_ms>=SHORT_MS)begin
       if(combo==3'b110)diagnostic<=!diagnostic;
       else if(combo==3'b111)effect_wet<=effect_wet>=224 ? 32 : effect_wet+32;
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
           profiles[focus*2+:2]<=profiles[focus*2+:2]==2 ? 0 : profiles[focus*2+:2]+1'b1;
          end else calibrate[focus]<=1;
        1:if(held[i]<EXPRESS_MS)presets[focus*2+:2]<=presets[focus*2+:2]+1'b1;
        2:if(held[i]>=LONG_MS)force_reset[focus]<=1;else focus<=!focus;
       endcase
      end
     end
    end
   end
  end
 end
endmodule
