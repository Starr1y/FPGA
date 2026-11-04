// Lightweight per-hand expression. Pitch is used only for motion vibrato.
module lite_hand_gesture #(parameter CLK_HZ=50000000)(
 input clk,rst_n,clear,enabled,invert,button_n,button2_n,pose_valid,playable,
 input signed[15:0]pitch,input[3:0]zone,input zone_valid,
 input hit,input[3:0]hit_zone,input[1:0]hit_profile,hit_octave,input chord,
 input glide_on,vibrato_on,input[8:0]glide_ms,input[1:0]input_profile,lesson_octave,input teaching,output button_event,output[31:0]button_payload,output combo_active,
 output pressed,output[1:0]octave,output octave_fresh,
 output[1:0]hit_octave_snapshot,output reg signed[15:0]bend,
 output reg[15:0]serial,output[55:0]debug_state,output pending,judging);
 wire[1:0]keys;wire holding;wire reset_state=clear || !playable;
 wire key_event;wire[31:0]key_data;wire combo;wire[7:0]strength;wire[3:0]blocked;
 s1s2_keys #(.CLK_HZ(CLK_HZ)) buttons(.clk(clk),.rst_n(rst_n),.clear(reset_state),.key_n({button2_n,button_n}),.pose_valid(pose_valid),.playable(playable),.zone_valid(zone_valid),.pitch(pitch),.zone(zone),.profile(input_profile),.teaching(teaching),.lesson_octave(lesson_octave),.event_valid(key_event),.payload(key_data),.combo(combo),.holding(holding),.pressed(keys),.octave(octave),.last_octave(hit_octave_snapshot),.strength(strength),.blocked(blocked));
 assign pressed=holding;assign octave_fresh=playable;assign pending=combo;assign judging=keys[1] && !holding;
 assign button_event=key_event;assign button_payload=key_data;assign combo_active=combo;
 reg target_valid;reg[6:0]base_note;reg[1:0]profile_q;
 wire map_ok,base_ok;wire[6:0]mapped,hit_note;
 dual_note_map live_map(.profile(profile_q),.zone(zone),.octave(octave),.chord(1'b0),.member(2'b0),.valid(map_ok),.midi_note(mapped));
 dual_note_map hit_map(.profile(hit_profile),.zone(hit_zone),.octave(hit_octave),.chord(1'b0),.member(2'b0),.valid(base_ok),.midi_note(hit_note));
 reg signed[15:0]reference,expression_base;reg old_holding;reg signed[15:0]target,current,vib;reg signed[23:0]baseline;reg pitch_seen;
 wire signed[16:0]directed=invert ? -$signed({pitch[15],pitch}) : $signed({pitch[15],pitch});
 wire signed[23:0]pitch_scaled=$signed(directed)<<<8;
 wire signed[23:0]motion=pitch_scaled-baseline;
 reg signed[23:0]motion_q;reg signed[31:0]vib_calc,dc_calc_q,dc_input_q;
 reg math_valid,expression_valid;reg signed[15:0]base_q;
 // Operand capture, shared constant arithmetic, then clamp/commit.
 // Clearing on ownership changes prevents an old pose reaching a new note.
 always @(posedge clk)begin
  if(!rst_n || reset_state || hit || holding!=old_holding)begin
   math_valid<=0;expression_valid<=0;motion_q<=0;vib_calc<=0;dc_input_q<=0;dc_calc_q<=0;base_q<=0;
  end else begin
   math_valid<=pose_valid && pitch_seen;expression_valid<=math_valid;
   if(pose_valid)begin motion_q<=motion;dc_input_q<=($signed(baseline)>>>8)-$signed(reference);base_q<=expression_base;end
   if(math_valid)begin vib_calc<=($signed(motion_q)>>>8)*40/16;dc_calc_q<=(dc_input_q*40)>>>4;end
  end
 end
 wire[6:0]destination;wire destination_ok;
 dual_note_map destination_map(.profile(key_data[24:23]),.zone(key_data[28:25]),.octave(key_data[22:21]),.chord(1'b0),.member(2'b0),.valid(destination_ok),.midi_note(destination));
 wire signed[15:0]zone_cents=($signed({1'b0,destination})-$signed({1'b0,base_note}))*16'sd100;
 wire signed[31:0]dc_amount=($signed(baseline)>>>8)-$signed(reference);
 wire signed[31:0]dc_cents=(dc_amount*40)>>>4;
 wire signed[31:0]dc_limited=dc_calc_q>1200 ? 1200 : dc_calc_q< -1200 ? -1200 : dc_calc_q;
 reg[31:0]divider;wire tick=divider==CLK_HZ/1000-1;
 reg[8:0]remaining,denom;reg div_busy,negative;reg[4:0]bits;
 reg[15:0]numerator,quotient;reg[9:0]remainder;
 wire[10:0]trial={remainder,numerator[15]};
 wire[15:0]next_quotient={quotient[14:0],trial>=denom};
 reg signed[16:0]delta;reg signed[16:0]combined;
 assign debug_state={blocked,strength,keys,holding,combo,8'd0,16'd0,current};
 always @(posedge clk)begin
  if(!rst_n)begin reference<=0;expression_base<=0;old_holding<=0;target_valid<=0;base_note<=60;profile_q<=0;target<=0;current<=0;vib<=0;baseline<=0;pitch_seen<=0;divider<=0;remaining<=0;denom<=1;div_busy<=0;negative<=0;bits<=0;numerator<=0;quotient<=0;remainder<=0;bend<=0;serial<=0;delta<=0;combined<=0;end
  else begin
   old_holding<=holding;
   if(tick)divider<=0;else divider<=divider+1'b1;
   if(reset_state)begin target_valid<=0;target<=0;current<=0;remaining<=0;div_busy<=0;vib<=0;pitch_seen<=0;bend<=0;end
   else begin
    if(pose_valid)begin
     if(!pitch_seen)begin baseline<=pitch_scaled;pitch_seen<=1;vib<=0;end
     else begin
      baseline<=baseline+(motion>>>3);

     end
    end
    if(expression_valid)begin
     if(!vibrato_on || !enabled || !holding)vib<=0;
     else if(vib_calc>50)vib<=50;else if(vib_calc< -50)vib<= -50;
     else if(vib_calc> -6 && vib_calc<6)vib<=0;else vib<=vib_calc;
    end
    if(hit)begin reference<=directed;baseline<=pitch_scaled;expression_base<=0;vib<=0;base_note<=hit_note;profile_q<=hit_profile;target_valid<=base_ok;target<=0;current<=0;remaining<=0;div_busy<=0;end
    else if(holding && !old_holding)begin reference<=directed;baseline<=pitch_scaled;expression_base<=current;target<=current;remaining<=0;div_busy<=0;vib<=0;end
    else if(holding && expression_valid && enabled)begin
     target<=base_q+(glide_on ? dc_limited : 0);remaining<=10;div_busy<=0;
    end
    else if(!holding && old_holding)begin current<=bend;target<=bend;remaining<=0;div_busy<=0;end
    else if(key_event && key_data[31:30]==0 && combo && glide_on && enabled && target_valid && destination_ok)begin
     target<=zone_cents>3600 ? 3600 : zone_cents< -3600 ? -3600 : zone_cents;
     remaining<=glide_ms<20 ? 20 : glide_ms>500 ? 500 : glide_ms;div_busy<=0;
    end
    else if(tick && remaining!=0 && !div_busy)begin
     delta=$signed(target)-$signed(current);negative<=delta<0;numerator<=delta<0 ? -delta : delta;quotient<=0;remainder<=0;bits<=16;denom<=remaining;div_busy<=1;
    end else if(div_busy)begin
     numerator<={numerator[14:0],1'b0};quotient<=next_quotient;
     remainder<=trial>=denom ? trial-denom : trial;
     if(bits==1)begin div_busy<=0;remaining<=remaining-1'b1;
      if(remaining==1)current<=target;else current<=negative ? current-next_quotient : current+next_quotient;
     end else bits<=bits-1'b1;
    end
    combined=$signed(current)+$signed(vibrato_on && holding ? vib : 16'sd0);
    if(combined>3600)combined=3600;if(combined< -3600)combined=-3600;
    if(bend!=combined[15:0])begin bend<=combined;serial<=serial+1'b1;end
   end
  end
 end
endmodule
