// Two fixed independent Voice banks, 16 per hand at VOICES=32.
// Consumer for two_hand_i2c_core: never truncate zone, epoch or hand ownership.
module dual_voice_scheduler #(
 parameter VOICES=32,CLK_HZ=50000000,HOLD_TICKS=(CLK_HZ/1000)*60,
 parameter VB=$clog2(VOICES),BANK=VOICES/2
)(input clk,rst_n,input event_valid,output event_ready,input[63:0]event_data,
 input[1:0]release_pending,output reg[1:0]release_ack,input[63:0]epochs,
 input chord_mode,input[5:0]preset_ids,input[3:0]release_ids,
 input[31:0]hold_ticks_left,hold_ticks_right,
 input[1:0]mono_glide,
 input[31:0]bend_cents,vibrato_cents,input[15:0]brightness,
 input[1:0]wrist_enabled,wrist_pressed,input[1:0]legato_enable,output legato_taken,input[31:0]wrist_bend,
 input[VOICES*16-1:0]envelopes,input[VOICES-1:0]release_due,
 output reg config_valid,output reg[127:0]config_data,input config_ready,
 output[VOICES*8-1:0]voice_brightness,
 output reg[VOICES-1:0]owned,gates,output[VOICES*7-1:0]notes,
 output reg[31:0]invalid_events,stolen_notes,
 output[VOICES-1:0]wrist_hold,
 output committed,output[7:0]committed_id,output committed_hand);
 reg[VOICES-1:0]latest_group;
 wire[VOICES-1:0]live_group;
 genvar lv;generate for(lv=0;lv<VOICES;lv=lv+1)begin:legato_live
  assign live_group[lv]=latest_group[lv] && gates[lv] && envelopes[lv*16+:16]!=0;
 end endgenerate
 wire left_live=|live_group[BANK-1:0],right_live=|live_group[VOICES-1:BANK];
 assign legato_taken=event_valid && event_ready && event_data[31:30]==0 && event_data[63:32]==(event_data[29] ? epochs[63:32] : epochs[31:0]) &&
  legato_enable[event_data[29]] && (event_data[29] ? right_live : left_live);
 reg[31:0]ftw[0:VOICES-1],ticks[0:VOICES-1],epoch[0:VOICES-1];
 // Internal configuration revision, not the external 32-bit cancellation epoch.
 // A config completes within a sample interval; 65536 intervening writes cannot
 // occur during one in-flight config. Narrow the revision increment path.
 reg[15:0]revision[0:VOICES-1];
 reg[7:0]ids[0:VOICES-1],age[0:VOICES-1],gain[0:VOICES-1];
 reg[6:0]midi[0:VOICES-1];reg[2:0]preset[0:VOICES-1];reg[1:0]tail[0:VOICES-1];
 reg[VOICES-1:0]dirty,retrigger,fast_stop;
 reg[31:0]midi_rom[0:127];
 reg[16:0]cent_rom[0:1199] /* synthesis syn_ramstyle="block_ram" */;
 initial begin
  if(VOICES<8 || VOICES%2!=0)$fatal(1,"Use an even VOICES count >=8 for two triad-capable banks");
  $readmemh("rtl/midi_ftw.hex",midi_rom);$readmemh("rtl/wrist_ratio.hex",cent_rom);
 end
 reg[31:0]old_epoch[0:1];reg[1:0]releasing;
 reg[31:0]old_bend,old_vibrato;
 reg[2:0]alloc_state;reg[63:0]pending;reg pending_chord;reg[1:0]member,pending_tail;reg[2:0]pending_preset;
 reg[VB-1:0]scan,choice,idle_choice,release_choice,active_choice;
 // Predecode the allocation write enables before touching the Voice bank.
 // This removes the choice-bit -> wide variable-index register-write fanout
 // seen in the routed critical paths, without adding an allocation cycle.
 reg[VOICES-1:0]choice_mask;
 reg idle_found,release_found,active_found;reg[15:0]quietest;reg[7:0]oldest;
 wire[VB-1:0]allocation_choice=idle_found ? idle_choice : release_found ? release_choice : active_choice;
 wire pending_hand=pending[29];wire[31:0]pending_epoch=pending[63:32];
 wire map_valid;wire[6:0]mapped_note;
 reg map_valid_q;reg[6:0]mapped_note_q;
 dual_note_map map(.profile(pending[24:23]),.zone(pending[28:25]),.octave(pending[22:21]),
  .chord(pending_chord),.member(member),.valid(map_valid),.midi_note(mapped_note));
 wire[15:0]scan_env=envelopes[scan*16+:16];
 wire[31:0]input_epoch=event_data[29] ? epochs[63:32] : epochs[31:0];
 wire[1:0]input_profile=event_data[24:23];wire[3:0]input_zone=event_data[28:25];
 wire input_valid=event_data[63:32]==input_epoch && input_profile<3 &&
  input_zone<(input_profile==1 ? 5 : input_profile==2 ? 12 : 7) && event_data[31:30]<2;
 assign event_ready=alloc_state==0 && !release_pending[event_data[29]] && !releasing[event_data[29]];
 reg[2:0]cfg_state;reg[VB-1:0]cfg_scan,current;
 reg[15:0]captured_revision;reg[31:0]captured_epoch;reg[7:0]captured_id,captured_gain;
 reg captured_gate,captured_trigger,captured_stop;reg[2:0]captured_preset;reg[1:0]captured_tail;
 // Local 16-Voice read banks, then a registered hand selection.
 reg [87:0] cfg_left_q,cfg_right_q;
 reg signed [16:0] cents_q;
 wire [VB-1:0] cfg_local=current>=BANK ? current-BANK : current;
 reg[48:0]frequency_product;reg[31:0]captured_ftw;
 wire cfg_hand=current>=BANK;
 assign committed=config_valid && config_ready && config_data[58] && config_data[56];
 assign committed_id=captured_id;assign committed_hand=cfg_hand;
 reg[VOICES-1:0]old_wrist_hold;
 reg signed[15:0]voice_bend[0:VOICES-1];
 reg[1:0]old_wrist_pressed;
 wire gesture_mode=wrist_enabled[cfg_hand]===1'b1;
 wire signed[16:0]cents=gesture_mode ? $signed(voice_bend[current]) :
    $signed(bend_cents[cfg_hand*16+:16])+$signed(vibrato_cents[cfg_hand*16+:16]);
 reg signed[16:0]bounded_cents;reg signed[2:0]octave_shift;
 reg[10:0]ratio_address;reg signed[2:0]shift_q,captured_shift;
 always @*begin
  bounded_cents=cents_q< -3600 ? -3600 : cents_q>3600 ? 3600 : cents_q;
  if(bounded_cents< -2400)begin ratio_address=bounded_cents+3600;octave_shift=-3;end
  else if(bounded_cents< -1200)begin ratio_address=bounded_cents+2400;octave_shift=-2;end
  else if(bounded_cents<0)begin ratio_address=bounded_cents+1200;octave_shift=-1;end
  else if(bounded_cents>=3600)begin ratio_address=0;octave_shift=3;end
  else if(bounded_cents>=2400)begin ratio_address=bounded_cents-2400;octave_shift=2;end
  else if(bounded_cents>=1200)begin ratio_address=bounded_cents-1200;octave_shift=1;end
  else begin ratio_address=bounded_cents;octave_shift=0;end
 end
 reg[10:0]ratio_address_q;reg[16:0]ratio_word_q;
 always @(posedge clk)ratio_word_q<=cent_rom[ratio_address_q];
 wire[48:0]shifted_product=captured_shift<0 ? frequency_product>>(-captured_shift) : frequency_product<<captured_shift;
 wire[1:0]wave;wire[15:0]attack,decay,sustain,release_step;
 timbre_presets presets(.preset_id(captured_preset),.release_id(captured_tail),.waveform(wave),
  .attack(attack),.decay(decay),.sustain(sustain),.release_coefficient(release_step));
 genvar v;
 generate for(v=0;v<VOICES;v=v+1)begin:display
  assign wrist_hold[v]=(wrist_enabled[v>=BANK]===1'b1) && (wrist_pressed[v>=BANK]===1'b1) && latest_group[v] && gates[v];
  assign notes[v*7+:7]=midi[v];assign voice_brightness[v*8+:8]=brightness[(v>=BANK)*8+:8];
 end endgenerate
 integer i,h;reg release_drained;
 always @(posedge clk)begin
  if(!rst_n)begin
   owned<=0;gates<=0;dirty<=0;retrigger<=0;fast_stop<=0;release_ack<=0;releasing<=0;
   old_epoch[0]<=0;old_epoch[1]<=0;old_bend<=0;old_vibrato<=0;
   alloc_state<=0;pending<=0;pending_chord<=0;member<=0;pending_preset<=0;pending_tail<=0;
   scan<=0;choice<=0;choice_mask<=0;idle_choice<=0;release_choice<=0;active_choice<=0;
   idle_found<=0;release_found<=0;active_found<=0;quietest<=65535;oldest<=0;
   cfg_left_q<=0;cfg_right_q<=0;cents_q<=0;cfg_state<=0;cfg_scan<=0;current<=0;config_valid<=0;config_data<=0;frequency_product<=0;captured_ftw<=0;ratio_address_q<=0;shift_q<=0;captured_shift<=0;latest_group<=0;old_wrist_hold<=0;old_wrist_pressed<=0;
   captured_revision<=0;captured_epoch<=0;captured_id<=0;captured_gain<=0;
   captured_gate<=0;captured_trigger<=0;captured_stop<=0;captured_preset<=0;captured_tail<=0;
   invalid_events<=0;stolen_notes<=0;map_valid_q<=0;mapped_note_q<=0;
   for(i=0;i<VOICES;i=i+1)begin voice_bend[i]<=0;ftw[i]<=0;ticks[i]<=0;epoch[i]<=0;revision[i]<=0;
    ids[i]<=0;age[i]<=0;gain[i]<=0;midi[i]<=0;preset[i]<=0;tail[i]<=0;end
  end else begin
   old_wrist_pressed<=wrist_pressed;old_wrist_hold<=wrist_hold;
   release_ack<=0;old_bend<=bend_cents;old_vibrato<=vibrato_cents;
   // Allocation scans a bank before consuming this registered map.
   map_valid_q<=map_valid;mapped_note_q<=mapped_note;
   // Config channel is immutable under backpressure. Revisions preserve later changes.
   case(cfg_state)
    0:begin if(dirty[cfg_scan])begin current<=cfg_scan;cfg_state<=6;end cfg_scan<=cfg_scan==VOICES-1 ? 0 : cfg_scan+1'b1;end
    // Split bend/vibrato addition, saturated ROM address, ROM read and DSP
    // multiplication into separate clocks. The owning Voice remains locked
    // in current and the existing revision/backpressure checks are retained.
    6:begin cents_q<=cents;captured_revision<=revision[current];cfg_state<=4;end
    4:begin ratio_address_q<=ratio_address;shift_q<=octave_shift;cfg_state<=5;end
    // Snapshot frequency and ownership together before the shared DSP.
    // Local-bank snapshot followed by registered hand selection (one extra slot).
    5:begin
     for(i=0;i<BANK;i=i+1)if(cfg_local==i)begin
      cfg_left_q<={ftw[i],epoch[i],ids[i],gain[i],gates[i],retrigger[i],fast_stop[i],preset[i],tail[i]};
      cfg_right_q<={ftw[i+BANK],epoch[i+BANK],ids[i+BANK],gain[i+BANK],gates[i+BANK],retrigger[i+BANK],fast_stop[i+BANK],preset[i+BANK],tail[i+BANK]};
     end
     captured_shift<=shift_q;cfg_state<=7;
    end
    7:begin
     {captured_ftw,captured_epoch,captured_id,captured_gain,captured_gate,captured_trigger,captured_stop,captured_preset,captured_tail}
       <=cfg_hand ? cfg_right_q : cfg_left_q;
     cfg_state<=1;
    end
    1:begin frequency_product<=captured_ftw*ratio_word_q;cfg_state<=2;end
    2:begin
     config_data<=0;config_data[7:0]<=current;config_data[39:8]<=shifted_product[47:16];config_data[47:40]<=captured_gain;
     config_data[49:48]<=wave;config_data[51:50]<=captured_preset[1:0];config_data[60]<=captured_preset[2];config_data[53:52]<=captured_tail;
     config_data[55]<=1;config_data[56]<=captured_gate;config_data[57]<=1;
     config_data[61]<=gesture_mode;config_data[58]<=captured_trigger;config_data[59]<=captured_stop;
     config_data[79:64]<=attack;config_data[95:80]<=decay;config_data[111:96]<=sustain;config_data[127:112]<=release_step;
     config_valid<=1;cfg_state<=3;
    end
    3:if(config_ready)begin
     config_valid<=0;cfg_state<=0;
     if(revision[current]==captured_revision)dirty[current]<=0;
     if(epoch[current]==captured_epoch && ids[current]==captured_id && captured_trigger)retrigger[current]<=0;
    end
   endcase
   // Gate expiry and expression refresh touch only the owning hand's bank.
   for(i=0;i<VOICES;i=i+1)if(owned[i])begin
    if(gates[i])begin
     if(release_due[i])begin gates[i]<=0;dirty[i]<=1;revision[i]<=revision[i]+1'b1;end
    end
    if(!(wrist_enabled[i>=BANK]===1'b1) && (bend_cents[(i>=BANK)*16+:16]!=old_bend[(i>=BANK)*16+:16] ||
       vibrato_cents[(i>=BANK)*16+:16]!=old_vibrato[(i>=BANK)*16+:16]))begin dirty[i]<=1;revision[i]<=revision[i]+1'b1;end
   end
   for(i=0;i<VOICES;i=i+1)begin
    if(latest_group[i] && gates[i] && wrist_enabled[i>=BANK] && $signed(voice_bend[i])!=$signed(wrist_bend[(i>=BANK)*16+:16]))begin
     voice_bend[i]<=wrist_bend[(i>=BANK)*16+:16];dirty[i]<=1;revision[i]<=revision[i]+1'b1;
    end
   end
   if(alloc_state==0 || (!release_pending[pending_hand] && pending_epoch==epochs[pending_hand*32+:32]))case(alloc_state)
    0:if(event_valid && event_ready)begin
     if(!input_valid)invalid_events<=invalid_events+1'b1;
     else if(legato_taken)begin end
     else if(event_data[31:30]==1)begin pending<=event_data;alloc_state<=7;end
     else begin
      for(i=0;i<VOICES;i=i+1)if((i>=BANK)==event_data[29])begin latest_group[i]<=0;
       if(wrist_hold[i])begin gates[i]<=0;dirty[i]<=1;revision[i]<=revision[i]+1'b1;end
      end
      pending<=event_data;pending_chord<=chord_mode && !event_data[29];member<=0;
      pending_preset<=preset_ids[event_data[29]*3+:3];pending_tail<=release_ids[event_data[29]*2+:2];alloc_state<=1;end
    end
    1:begin scan<=pending_hand ? BANK : 0;idle_found<=0;release_found<=0;active_found<=0;quietest<=65535;oldest<=0;alloc_state<=2;end
    2:begin
     if(!idle_found && !gates[scan] && scan_env==0 && !retrigger[scan] && !dirty[scan] && !(cfg_state!=0 && current==scan))begin idle_choice<=scan;idle_found<=1;end
     if(!gates[scan] && !retrigger[scan] && (!release_found || scan_env<quietest))begin release_choice<=scan;release_found<=1;quietest<=scan_env;end
     if(gates[scan] && (!active_found || age[scan]>oldest))begin active_choice<=scan;active_found<=1;oldest<=age[scan];end
     if(scan==(pending_hand ? VOICES-1 : BANK-1))alloc_state<=3;else scan<=scan+1'b1;
    end
    3:begin
     choice<=allocation_choice;
     for(i=0;i<VOICES;i=i+1)choice_mask[i]<=allocation_choice==i;
     alloc_state<=4;
    end
    4:begin
     if(!map_valid_q)begin invalid_events<=invalid_events+1'b1;alloc_state<=0;end
     else if(gates[choice] || envelopes[choice*16+:16]!=0 || retrigger[choice] || dirty[choice] || (cfg_state!=0 && current==choice))begin
      for(i=0;i<VOICES;i=i+1)if(choice_mask[i])begin
       gates[i]<=0;fast_stop[i]<=1;dirty[i]<=1;retrigger[i]<=0;revision[i]<=revision[i]+1'b1;
      end
      stolen_notes<=stolen_notes+1'b1;alloc_state<=5;
     end else alloc_state<=6;
    end
    5:if(envelopes[choice*16+:16]==0 && !dirty[choice] && !(cfg_state!=0 && current==choice))alloc_state<=6;
    6:begin
     if(mono_glide[pending_hand] && !pending_chord)begin
      for(i=0;i<VOICES;i=i+1)if(!choice_mask[i] && owned[i] && (i>=BANK)==pending_hand)begin
       gates[i]<=0;fast_stop[i]<=1;dirty[i]<=1;retrigger[i]<=0;revision[i]<=revision[i]+1'b1;
      end
     end
     for(i=0;i<VOICES;i=i+1)if(choice_mask[i])begin
      latest_group[i]<=1;voice_bend[i]<=0;owned[i]<=1;gates[i]<=1;dirty[i]<=1;retrigger[i]<=1;fast_stop[i]<=0;
      ftw[i]<=midi_rom[mapped_note_q];midi[i]<=mapped_note_q;
      epoch[i]<=pending_epoch;ids[i]<=pending[11:4];gain[i]<={pending[20:14],1'b0};
      preset[i]<=pending_preset;tail[i]<=pending_tail;ticks[i]<=0;age[i]<=0;revision[i]<=revision[i]+1'b1;
     end
     for(i=0;i<VOICES;i=i+1)if(!choice_mask[i] && owned[i] && (i>=BANK)==pending_hand && age[i]!=255)age[i]<=age[i]+1'b1;
     if(pending_chord && member<2)begin member<=member+1'b1;alloc_state<=1;end else alloc_state<=0;
    end
    // Latch the queue event before updating all matching Voice revisions.
    // Cancellation below takes precedence over this delayed gain update.
    7:begin
     for(i=0;i<VOICES;i=i+1)if(latest_group[i] && owned[i] && (i>=BANK)==pending_hand && epoch[i]==pending_epoch && ids[i]==pending[11:4])begin
      gain[i]<={pending[20:14],1'b0};dirty[i]<=1;revision[i]<=revision[i]+1'b1;
     end
     alloc_state<=0;
    end
   endcase
   // Cancellation can occur while a config is held. Drain that config, then
   // send gate-off configs before acknowledging; retain release tails/pitch.
   for(h=0;h<2;h=h+1)begin
    if(!release_pending[h])releasing[h]<=0;
    if(release_pending[h] && (!releasing[h] || old_epoch[h]!=epochs[h*32+:32]))begin
     releasing[h]<=1;old_epoch[h]<=epochs[h*32+:32];
     for(i=0;i<VOICES;i=i+1)if((i>=BANK)==h && owned[i])begin
       latest_group[i]<=0;gates[i]<=0;retrigger[i]<=0;fast_stop[i]<=1;dirty[i]<=1;revision[i]<=revision[i]+1'b1;
     end
    end else if(release_pending[h] && releasing[h])begin
     release_drained=1;
     for(i=0;i<VOICES;i=i+1)if((i>=BANK)==h && (dirty[i] || gates[i] || retrigger[i]))release_drained=0;
     if(cfg_state!=0 && (current>=BANK)==h)release_drained=0;
     if(release_drained)release_ack[h]<=1;
    end
   end
   if(alloc_state!=0 && (release_pending[pending_hand] || pending_epoch!=epochs[pending_hand*32+:32]))alloc_state<=0;
  end
 end
endmodule

