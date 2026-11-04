// KEY30 per-hand physical/virtual buttons. All timestamps use core clock.
module s1s2_keys #(parameter CLK_HZ=50000000)(
 input clk,rst_n,clear,input[1:0]key_n,input pose_valid,playable,zone_valid,
 input signed[15:0]pitch,input[3:0]zone,input[1:0]profile,
 input teaching,input[1:0]lesson_octave,
 output reg event_valid,output reg[31:0]payload,output reg combo,
 output reg holding,output[1:0]pressed,output reg[1:0]octave,
 output reg[1:0]last_octave,output reg[7:0]strength,output reg[3:0]blocked);
 reg[1:0]s1,s2,stable,old,armed;reg[2:0]db[0:1];reg[31:0]divider,pose_age;
 reg[15:0]held1,held2;reg consumed,active,heavy;reg[7:0]event_id;
 reg signed[15:0]filtered;reg pose_seen;integer i;
 wire tick=divider==CLK_HZ/1000-1;assign pressed=~stable & armed;
 wire[1:0]preview=filtered<0 ? 2'd3 : filtered>480 ? 2'd1 : 2'd0;
 always @(posedge clk)begin
  if(!rst_n)begin s1<=3;s2<=3;stable<=3;old<=0;armed<=0;divider<=0;pose_age<=CLK_HZ;held1<=0;held2<=0;consumed<=0;active<=0;heavy<=0;event_id<=0;event_valid<=0;payload<=0;combo<=0;holding<=0;octave<=0;last_octave<=0;strength<=48;blocked<=0;filtered<=0;pose_seen<=0;for(i=0;i<2;i=i+1)db[i]<=0;end
  else begin
   s1<=key_n;s2<=s1;event_valid<=0;
   if(tick)divider<=0;else divider<=divider+1'b1;
   if(pose_valid)begin filtered<=pose_seen && ($signed(filtered)-$signed(pitch)>1 || $signed(filtered)-$signed(pitch)< -1) ? ($signed(filtered)+$signed(pitch))>>>1 : pitch;pose_seen<=1;pose_age<=0;end
   else if(pose_age<CLK_HZ)pose_age<=pose_age+1'b1;
   octave<=teaching ? lesson_octave : preview;
   if(clear)begin armed<=0;old<=0;held1<=0;held2<=0;consumed<=0;active<=0;heavy<=0;holding<=0;combo<=0;pose_seen<=0;blocked<=0;end
   else if(tick)begin
    for(i=0;i<2;i=i+1)begin
     if(s2[i]==stable[i])db[i]<=0;else if(db[i]==4)begin stable[i]<=s2[i];db[i]<=0;end else db[i]<=db[i]+1'b1;
     if(s2[i] && stable[i])armed[i]<=1;
    end
    old<=pressed;
    if(pressed[1])begin if(held2<65535)held2<=held2+1'b1;if(held2>=179 && !consumed && !teaching)holding<=1;end
    else begin held2<=0;holding<=0;consumed<=0;end
    if(pressed[0] && !old[0])begin
     held1<=0;heavy<=0;active<=0;blocked<=0;
     if(!playable || !pose_seen || pose_age>CLK_HZ*15/1000)blocked<=1;
     else if(!zone_valid)blocked<=2;
     else begin
      active<=1;event_id<=event_id+1'b1;event_valid<=1;strength<=48;last_octave<=teaching ? lesson_octave : preview;
      combo<=!teaching && pressed[1] && old[1] && !holding && !consumed && held2<80;
      if(pressed[1] && old[1] && !holding && held2<80)consumed<=1;
      payload<={2'd0,1'b0,zone,profile,(teaching ? lesson_octave : preview),7'd48,2'b0,event_id+8'd1,4'b0};
     end
    end else if(pressed[0])begin
     if(held1<65535)held1<=held1+1'b1;
     if(active && !heavy && held1>=219)begin heavy<=1;strength<=112;event_valid<=1;payload[31:30]<=1;payload[20:14]<=112;end
    end
    if(!pressed[0] && old[0])begin
     // Short press stays at its initial light strength; no release event needed.
     active<=0;
    end
   end
  end
 end
endmodule

