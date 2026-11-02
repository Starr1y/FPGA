// Semantic events from performance_controls. No pin assignment or display.
// Parameters are stable registers; note acceptance snapshots them in the synth.
module duo_parameters(input clk,rst_n,enabled,input[11:0]board_actions,
 input encoder_step,encoder_direction,encoder_short,encoder_long,pedal_toggle,
 input[1:0]wrist_short,wrist_long,
 output reg focus,editing,visible,diagnostic,output reg[1:0]imu_enabled,force_reset,output reg[3:0]page,
 output reg[3:0]presets,release_ids,profiles,
 output reg chord_mode,muted,output reg[1:0]effect_mode,calibrate,
 output reg[7:0]effect_wet,chorus_depth,
 output[13:0]delay_samples,output[7:0]feedback);
 localparam LAST_PAGE=10;
 reg[13:0]delay_echo,delay_chorus,delay_reverb;
 reg[7:0]feedback_echo,feedback_reverb;
 assign delay_samples=effect_mode==2 ? delay_chorus : effect_mode==3 ? delay_reverb : delay_echo;
 assign feedback=effect_mode==2 ? 0 : effect_mode==3 ? feedback_reverb : feedback_echo;
 function[7:0]step8(input[7:0]n,input up,input[7:0]step,limit);
  reg[8:0]wide;
  begin wide={1'b0,n}+{1'b0,step};step8=up ? (wide>limit ? limit : wide[7:0]) : n<step ? 0 : n-step;end
 endfunction
 function[13:0]step_delay(input[13:0]n,input up);
  begin step_delay=up ? (n>=16320 ? 16368 : n+48) : n<=96 ? 48 : n-48;end
 endfunction
 integer h;
 always @(posedge clk)begin
  if(!rst_n)begin
   diagnostic<=0;imu_enabled<=0;force_reset<=0;focus<=0;editing<=0;visible<=0;page<=0;presets<=0;release_ids<=4'b0101;profiles<=0;chord_mode<=0;muted<=1;
   effect_mode<=0;effect_wet<=128;chorus_depth<=96;calibrate<=0;
   delay_echo<=4800;delay_chorus<=576;delay_reverb<=3840;feedback_echo<=96;feedback_reverb<=80;
  end else begin
   calibrate<=0;force_reset<=0;
   if(!enabled)begin editing<=0;visible<=0;end
   else begin
    // Button actions win over simultaneous rotation, never change a hidden field.
    if(encoder_long)begin editing<=0;if(!editing)begin page<=0;visible<=0;end end
    else if(encoder_short)begin visible<=1;if(visible)editing<=!editing;end
    else if(encoder_step)begin
     visible<=1;
     if(!editing)page<=encoder_direction ? (page==LAST_PAGE ? 0 : page+1'b1) : (page==0 ? LAST_PAGE : page-1'b1);
     else case(page)
      0:focus<=encoder_direction;
      1:if(encoder_direction && presets[focus*2+:2]<3)presets[focus*2+:2]<=presets[focus*2+:2]+1'b1;
        else if(!encoder_direction && presets[focus*2+:2]!=0)presets[focus*2+:2]<=presets[focus*2+:2]-1'b1;
      2:if(encoder_direction && release_ids[focus*2+:2]<2)release_ids[focus*2+:2]<=release_ids[focus*2+:2]+1'b1;
        else if(!encoder_direction && release_ids[focus*2+:2]!=0)release_ids[focus*2+:2]<=release_ids[focus*2+:2]-1'b1;
      3:if(encoder_direction && effect_mode<3)effect_mode<=effect_mode+1'b1;
        else if(!encoder_direction && effect_mode!=0)effect_mode<=effect_mode-1'b1;
      4:effect_wet<=step8(effect_wet,encoder_direction,16,255);
      5:case(effect_mode)
        2:delay_chorus<=step_delay(delay_chorus,encoder_direction);
        3:delay_reverb<=step_delay(delay_reverb,encoder_direction);
        default:delay_echo<=step_delay(delay_echo,encoder_direction);
       endcase
      6:if(effect_mode==3)feedback_reverb<=step8(feedback_reverb,encoder_direction,8,128);
        else if(effect_mode!=2)feedback_echo<=step8(feedback_echo,encoder_direction,8,192);
      7:chorus_depth<=step8(chorus_depth,encoder_direction,16,255);
      8:chord_mode<=encoder_direction;
      9:muted<=encoder_direction;
      10:if(encoder_direction && profiles[focus*2+:2]<2)profiles[focus*2+:2]<=profiles[focus*2+:2]+1'b1;
         else if(!encoder_direction && profiles[focus*2+:2]!=0)profiles[focus*2+:2]<=profiles[focus*2+:2]-1'b1;
     endcase
    end
    // Foot mode has priority over a simultaneous edit of the mode item.
    if(pedal_toggle)chord_mode<=!chord_mode;
    for(h=0;h<2;h=h+1)begin
     if(wrist_long[h])profiles[h*2+:2]<=profiles[h*2+:2]==2 ? 0 : profiles[h*2+:2]+1'b1;
     else if(wrist_short[h] && imu_enabled[h])calibrate[h]<=1;
    end
   end

   // Board actions take precedence over an edit of the same parameter.
   // All state is stored here; there is no shadow copy in either decoder.
   if(board_actions[0])calibrate[focus]<=1;
   if(board_actions[1])profiles[focus*2+:2]<=profiles[focus*2+:2]==2 ? 0 : profiles[focus*2+:2]+1'b1;
   if(board_actions[2])presets[focus*2+:2]<=presets[focus*2+:2]+1'b1;
   if(board_actions[3])focus<=!focus;
   if(board_actions[4])force_reset[focus]<=1;
   if(board_actions[5])imu_enabled[focus]<=!imu_enabled[focus];
   if(board_actions[6])begin diagnostic<=!diagnostic;visible<=0;editing<=0;end
   if(board_actions[7])muted<=!muted;
   if(board_actions[8])chord_mode<=!chord_mode;
   if(board_actions[9])effect_mode<=effect_mode+1'b1;
   if(board_actions[10])effect_wet<=effect_wet>=224 ? 32 : effect_wet+32;
   if(board_actions[11])begin visible<=!visible;editing<=0;page<=0;diagnostic<=0;end
  end
 end
endmodule
