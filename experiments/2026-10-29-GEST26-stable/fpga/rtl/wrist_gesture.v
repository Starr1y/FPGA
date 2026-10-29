// Q4 degrees, Q4 cents internally. Independent state for ONE hand.
// 1ms enables are not clocks. History stores stable octave with wall time.
module wrist_gesture #(parameter CLK_HZ=50000000)(
 input clk,rst_n,clear,enabled,invert,button_n,pose_valid,playable,
 input signed[15:0]pitch,input[3:0]zone,input zone_valid,
 input hit,input[3:0]hit_zone,input[1:0]hit_profile,hit_octave,input chord,
 output reg pressed,output reg[1:0]octave,output reg octave_fresh,
 output reg[1:0]hit_octave_snapshot,output reg signed[15:0]bend,
 output reg[15:0]serial,output[55:0]debug_state
);
 reg s1,s2,stable,armed;reg[3:0]db;reg[31:0]divider,ms,pose_ms;
 wire tick=divider==CLK_HZ/1000-1;
 reg[31:0]last_eval_ms;reg[3:0]filter_pipe;reg signed[23:0]pose_q,delta_q,scaled_q;reg signed[31:0]pitch_dead,pitch_limited;
 reg signed[23:0]filtered;reg signed[23:0]reference;
 reg filters_ready,old_pressed;reg[1:0]candidate;reg[5:0]stable_ms;
 reg[1:0]history[0:15];reg[7:0]history_ms[0:15];reg[3:0]wr;
 reg[3:0]history_div;reg[4:0]history_count;
 reg[1:0]profile_q,octave_q;reg[3:0]zone_q;
 reg signed[15:0]zone_current,zone_target;
 reg signed[23:0]zone_accumulator,zone_step;reg[5:0]zone_remaining;
 reg signed[15:0]requested_zone;
 reg div_busy,div_negative;reg[4:0]div_bits;
 reg[24:0]div_numerator,div_quotient;reg[6:0]div_remainder;
 reg signed[24:0]div_delta;
 wire[7:0]div_trial={div_remainder,div_numerator[24]};
 wire[24:0]div_next_q={div_quotient[23:0],div_trial>=60};
 reg[6:0]base_note,top_note;reg target_valid;
 reg signed[31:0]pitch_amount,total,limited;
 reg signed[15:0]lower,upper;reg[1:0]next_octave;
 assign debug_state={filtered,reference,candidate,stable_ms};
 integer j;wire[3:0]history_read=wr-4'd7;wire[7:0]history_age=ms[7:0]-history_ms[history_read];
 reg signed[31:0]pitch_difference;
 function signed[15:0]cent100;input signed[15:0]n;begin cent100=(n<<<6)+(n<<<5)+(n<<<2);end endfunction
 wire signed[16:0]directed=invert ? -$signed({pitch[15],pitch}) : $signed({pitch[15],pitch});
 wire signed[23:0]filter_difference=($signed(directed)<<<4)-filtered;
 function[4:0]degree;input[1:0]p;input[3:0]z;
 begin case(p)
 0:case(z)0:degree=0;1:degree=2;2:degree=4;3:degree=5;4:degree=7;5:degree=9;6:degree=11;7:degree=12;8:degree=14;default:degree=16;endcase
 1:case(z)0:degree=0;1:degree=2;2:degree=4;3:degree=7;default:degree=9;endcase
 default:degree={1'b0,z};endcase end endfunction
 function[6:0]root;input[1:0]o;begin case(o)2:root=36;3:root=48;0:root=60;default:root=72;endcase end endfunction
 always @*begin
  requested_zone=cent100($signed({1'b0,degree(profile_q,zone)})-$signed({1'b0,degree(profile_q,zone_q)}));
  // Direct destination selection allows C2<->C5 without two extra 30ms dwells.
  next_octave=filtered< -30*256 ? 2 : filtered< -10*256 ? 3 : filtered<20*256 ? 0 : 1;
  case(octave)
   2:if(filtered<= -27*256)next_octave=2;
   3:if(filtered>= -33*256 && filtered<= -7*256)next_octave=3;
   0:if(filtered>= -13*256 && filtered<=23*256)next_octave=0;
   1:if(filtered>=17*256)next_octave=1;
  endcase
  // filtered Q8 degrees: Q4 cents = degrees * 40 *16.


  lower=-2400;upper=2400;
  if(cent100($signed({1'b0,base_note})-16'sd36)<2400)lower=-(cent100($signed({1'b0,base_note})-16'sd36));
  if(cent100(16'sd96-$signed({1'b0,top_note}))<2400)upper=cent100(16'sd96-$signed({1'b0,top_note}));

 end
 always @(posedge clk)begin
  if(!rst_n)begin
   last_eval_ms<=0;filter_pipe<=0;pose_q<=0;delta_q<=0;scaled_q<=0;pitch_difference<=0;pitch_amount<=0;pitch_dead<=0;pitch_limited<=0;total<=0;limited<=0;
   div_busy<=0;div_negative<=0;div_bits<=0;div_numerator<=0;div_quotient<=0;div_remainder<=0;div_delta<=0;
   s1<=1;s2<=1;stable<=1;armed<=0;db<=0;divider<=0;ms<=0;pose_ms<=0;
   pressed<=0;old_pressed<=0;octave<=0;candidate<=0;stable_ms<=0;
   filtered<=0;reference<=0;filters_ready<=0;wr<=0;history_div<=0;history_count<=0;
   hit_octave_snapshot<=0;octave_fresh<=0;bend<=0;serial<=0;profile_q<=0;octave_q<=0;zone_q<=0;
   zone_current<=0;zone_target<=0;zone_accumulator<=0;zone_step<=0;zone_remaining<=0;div_busy<=0;base_note<=60;top_note<=60;target_valid<=0;
   for(j=0;j<16;j=j+1)begin history[j]<=0;history_ms[j]<=0;end
  end else begin
   s1<=button_n;s2<=s1;divider<=tick ? 0 : divider+1'b1;old_pressed<=pressed;
   filter_pipe<={filter_pipe[2:0],pose_valid && playable};
   if(pose_valid && playable)begin pose_ms<=ms;pose_q<=directed<<<4;end
   if(filter_pipe[0])delta_q<=pose_q-filtered;
   if(filter_pipe[1])scaled_q<=(delta_q<<<1)+delta_q;
   if(filter_pipe[2])begin
    if(!filters_ready)begin filtered<=pose_q;filters_ready<=1;end
    else filtered<=filtered+(scaled_q>>>3);
   end
   // Registered stages: no reference-to-bend subtract/scale/clamp chain.
   pitch_difference<=$signed(filtered)-$signed(reference);
   pitch_amount<=((pitch_difference<<<2)+pitch_difference)>>>1;
   pitch_dead<=pitch_amount>96 ? pitch_amount-96 : pitch_amount< -96 ? pitch_amount+96 : 0;
   pitch_limited<=pitch_dead>19200 ? 19200 : pitch_dead< -19200 ? -19200 : pitch_dead;
   total<=(pitch_limited>>>4)+zone_current;
   limited<=total<lower ? lower : total>upper ? upper : total;
   if(div_busy)begin
    div_numerator<=div_numerator<<1;div_quotient<=div_next_q;
    div_remainder<=div_trial>=60 ? div_trial-60 : div_trial;
    if(div_bits==0)begin div_busy<=0;zone_step<=div_negative ? -$signed(div_next_q) : $signed(div_next_q);zone_remaining<=60;end
    else div_bits<=div_bits-1'b1;
   end
   if(filter_pipe[3] && !pressed && filters_ready && playable)begin
    last_eval_ms<=pose_ms;
    if(candidate!=next_octave || pose_ms-last_eval_ms>20)begin candidate<=next_octave;stable_ms<=0;end
    else if(stable_ms<30)begin
     if(pose_ms-last_eval_ms>=30-stable_ms)begin stable_ms<=30;octave<=candidate;end
     else stable_ms<=stable_ms+(pose_ms-last_eval_ms);
    end else octave<=candidate;
   end
   if(tick)begin
    ms<=ms+1'b1;
    if(s2==stable)db<=0;else if(db==9)begin stable<=s2;db<=0;end else db<=db+1'b1;
    if(stable && s2)armed<=1;
    pressed<=armed && !stable && enabled && playable && ms-pose_ms<40;
    if(history_div==4)begin
     history_div<=0;history[wr]<=octave;history_ms[wr]<=ms[7:0];wr<=wr+1'b1;
     if(history_count<16)history_count<=history_count+1'b1;
    end else history_div<=history_div+1'b1;
    if(history_count>=7 && history_age>=30 && history_age<=80)hit_octave_snapshot<=pressed && target_valid ? octave_q : history[history_read];
    octave_fresh<=history_count>=7 && history_age>=30 && history_age<=80 && playable && filters_ready && ms-pose_ms<40;
    if(pressed && target_valid)begin
     if(zone_valid && requested_zone!=zone_target && !div_busy)begin
      zone_target<=requested_zone;zone_accumulator<=$signed(zone_current)*256;
      div_delta=($signed({{9{requested_zone[15]}},requested_zone})-$signed({{9{zone_current[15]}},zone_current}))<<<8;
      div_negative<=div_delta<0;div_numerator<=div_delta<0 ? -div_delta : div_delta;
      div_quotient<=0;div_remainder<=0;div_bits<=24;div_busy<=1;zone_remaining<=0;
     end else if(zone_remaining!=0)begin
      zone_remaining<=zone_remaining-1'b1;
      if(zone_remaining==1)zone_current<=zone_target;
      else begin zone_accumulator<=zone_accumulator+zone_step;zone_current<=(zone_accumulator+zone_step)>>>8;end
     end
     bend<=limited[15:0];
    end
   end
   if(pressed && !old_pressed)begin if(target_valid)octave<=octave_q;reference<=filtered;zone_q<=zone;zone_current<=0;zone_target<=0;zone_accumulator<=0;zone_step<=0;zone_remaining<=0;div_busy<=0;end
   if(hit)begin
    reference<=filtered;profile_q<=hit_profile;octave_q<=hit_octave;zone_q<=hit_zone;
    base_note<=root(hit_octave)+degree(hit_profile,hit_zone);
    top_note<=root(hit_octave)+degree(hit_profile,hit_zone)+(chord ? (hit_profile==0 ? degree(0,hit_zone+4)-degree(0,hit_zone) : 7) : 0);
    zone_current<=0;zone_target<=0;zone_accumulator<=0;zone_step<=0;zone_remaining<=0;div_busy<=0;bend<=0;target_valid<=1;serial<=serial+1'b1;
   end
   if(clear || !enabled || !playable || ms-pose_ms>=40)begin
    pressed<=0;old_pressed<=0;armed<=0;target_valid<=0;bend<=0;zone_current<=0;zone_target<=0;zone_accumulator<=0;zone_step<=0;zone_remaining<=0;div_busy<=0;
    if(!playable || ms-pose_ms>=40)begin history_count<=0;history_div<=0;octave_fresh<=0;stable_ms<=0;end
    if(clear)begin filter_pipe<=0;filters_ready<=0;history_count<=0;wr<=0;history_div<=0;octave_fresh<=0;candidate<=octave;stable_ms<=0;end
   end
  end
 end
endmodule
