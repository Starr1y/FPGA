// Event FIFO and sequential allocation; 32 independent Voice owners/states.
// Empty first, quiet Release next, then oldest/weakest active. Steals fade first.
module local_instrument #(
 parameter CLK_HZ=50000000,parameter HOLD_TICKS=(CLK_HZ/1000)*60,
 parameter VOICES=4,parameter VOICE_BITS=$clog2(VOICES),parameter FIFO_DEPTH=8
)(
 input clk,input rst_n,input enabled,input note_on,velocity_update,input [2:0] hit_zone,
 input signed [1:0] hit_octave,input [7:0] velocity,event_id,
 input signed [15:0] bend_cents,vibrato_cents,input [VOICES*16-1:0] envelopes,
 input preset_enable,input [1:0] preset_id,release_id,
 input external_valid,input [127:0] external_data,
 output reg config_valid,output reg [127:0] config_data,input config_ready,
 output reg [VOICES-1:0] owned,output [VOICES-1:0] gates,output [VOICES*3-1:0] zones,
 output reg [31:0] stolen_notes,event_drops
);
 reg [31:0] base_ftw[0:VOICES-1],gate_ticks[0:VOICES-1];
 reg [7:0] age[0:VOICES-1],gain[0:VOICES-1],voice_event[0:VOICES-1],revision[0:VOICES-1];
 reg [VOICES-1:0] gate,dirty,retrigger_pending,voice_preset_enabled,external_gate,fast_stop;
 reg [2:0] voice_zone[0:VOICES-1];reg [1:0] voice_preset[0:VOICES-1],voice_release[0:VOICES-1];
 reg [1:0] state;reg [VOICE_BITS-1:0] current_voice,config_scan;
 reg [7:0] sent_revision,sent_event,captured_gain;
 reg captured_gate,captured_retrigger,captured_preset_enabled,captured_fast_stop;
 reg [1:0] captured_preset,captured_release;
 wire [1:0] preset_wave;wire [15:0] preset_attack,preset_decay,preset_sustain,preset_release_coefficient;
 timbre_presets presets(.preset_id(captured_preset),.release_id(captured_release),.waveform(preset_wave),
  .attack(preset_attack),.decay(preset_decay),.sustain(preset_sustain),.release_coefficient(preset_release_coefficient));
 reg signed [15:0] previous_bend,previous_vibrato;
 reg [19:0] ratio_rom[0:511];reg [16:0] ratio;
 wire signed [16:0] cents=$signed(bend_cents)+$signed(vibrato_cents);
 wire [8:0] ratio_address=cents< -230 ? 0 : cents>230 ? 460 : cents+230;
 reg [48:0] frequency_product;
 initial $readmemh("rtl/cent_ratio.hex",ratio_rom);
 wire [19:0] ratio_word=ratio_rom[ratio_address];
 always @(posedge clk)ratio<=ratio_word[16:0];
 localparam FIFO_BITS=$clog2(FIFO_DEPTH);
 reg [25:0] event_fifo[0:FIFO_DEPTH-1];reg [FIFO_BITS-1:0] event_wr,event_rd;
 reg [FIFO_BITS:0] event_count;reg [25:0] pending_event;
 reg [2:0] alloc_state;reg [VOICE_BITS-1:0] alloc_scan,idle_choice,release_choice,active_choice,fade_voice;
 reg idle_found,release_found,active_found,eligible_seen,fade_completed;
 reg [15:0] minimum_release,minimum_active;reg [7:0] oldest;
 wire [15:0] scan_env=envelopes[alloc_scan*16+:16];
 reg [VOICE_BITS-1:0] chosen_voice;
 reg chosen_alive;
 wire selected_alive=gate[chosen_voice] || envelopes[chosen_voice*16+:16]!=0 || retrigger_pending[chosen_voice];
 wire event_pop=enabled && alloc_state==5 && eligible_seen && !external_valid && (fade_completed || !chosen_alive);
 wire valid_event=enabled && note_on && hit_zone<7;
 wire event_push=valid_event && (event_count<FIFO_DEPTH || event_pop);
 assign gates=gate & owned;
 genvar z;
 generate for(z=0;z<VOICES;z=z+1)begin: zone_bus
  assign zones[z*3+:3]=voice_zone[z];
 end endgenerate
 integer i;
    function [31:0] note_ftw;
        input [2:0] zone;
        input signed [1:0] octave;
        reg [31:0] ftw;
        begin
            case(zone)
                0:ftw=23409859;1:ftw=26276679;2:ftw=29494575;3:ftw=31248413;
                4:ftw=35075158;5:ftw=39370534;6:ftw=44191930;
                default:ftw=0;
            endcase
            note_ftw=octave<0 ? ftw>>1 : octave>0 ? ftw<<1 : ftw;
        end
    endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;current_voice<=0;config_scan<=0;config_valid<=0;config_data<=0;
   owned<=0;gate<=0;dirty<=0;retrigger_pending<=0;external_gate<=0;fast_stop<=0;
   stolen_notes<=0;event_drops<=0;frequency_product<=0;sent_revision<=0;sent_event<=0;
   captured_gain<=0;captured_gate<=0;captured_retrigger<=0;captured_fast_stop<=0;
   previous_bend<=0;previous_vibrato<=0;voice_preset_enabled<=0;
   captured_preset<=0;captured_release<=0;captured_preset_enabled<=0;
   event_wr<=0;event_rd<=0;event_count<=0;pending_event<=0;alloc_state<=0;alloc_scan<=0;
   idle_choice<=0;release_choice<=0;active_choice<=0;fade_voice<=0;
   chosen_voice<=0;chosen_alive<=0;
   idle_found<=0;release_found<=0;active_found<=0;eligible_seen<=0;fade_completed<=0;
   minimum_release<=65535;minimum_active<=65535;oldest<=0;
   for(i=0;i<VOICES;i=i+1)begin
    base_ftw[i]<=0;gate_ticks[i]<=0;age[i]<=0;gain[i]<=0;voice_event[i]<=0;revision[i]<=0;
    voice_zone[i]<=3;voice_preset[i]<=0;voice_release[i]<=0;
   end
  end else begin
   previous_bend<=bend_cents;previous_vibrato<=vibrato_cents;
   if(event_push)begin
    event_fifo[event_wr]<={hit_zone,hit_octave,velocity,event_id,preset_enable,preset_id,release_id};
    event_wr<=event_wr+1'b1;
   end else if(valid_event)event_drops<=event_drops+1'b1;
   if(event_pop)event_rd<=event_rd+1'b1;
   case({event_push,event_pop})2'b10:event_count<=event_count+1'b1;2'b01:event_count<=event_count-1'b1;endcase
   case(state)
    0:begin
     if(dirty[config_scan])begin current_voice<=config_scan;state<=1;end
     config_scan<=config_scan==VOICES-1 ? 0 : config_scan+1'b1;
    end
    1:begin
     frequency_product<=base_ftw[current_voice]*ratio;
     captured_gain<=gain[current_voice];captured_gate<=gate[current_voice];
     captured_preset<=voice_preset[current_voice];captured_release<=voice_release[current_voice];
     captured_preset_enabled<=voice_preset_enabled[current_voice];captured_fast_stop<=fast_stop[current_voice];
     captured_retrigger<=retrigger_pending[current_voice];sent_revision<=revision[current_voice];
     sent_event<=voice_event[current_voice];state<=2;
    end
    2:begin
     config_data<=0;config_data[7:0]<=current_voice;config_data[39:8]<=frequency_product[47:16];
     config_data[47:40]<=captured_gain;config_data[49:48]<=captured_preset_enabled ? preset_wave : 2'd3;
     config_data[51:50]<=captured_preset;config_data[53:52]<=captured_release;config_data[55]<=captured_preset_enabled;
     config_data[56]<=captured_gate;config_data[57]<=1;config_data[58]<=captured_retrigger;config_data[59]<=captured_fast_stop;
     config_data[79:64]<=captured_preset_enabled ? preset_attack : 16'd341;
     config_data[95:80]<=captured_preset_enabled ? preset_decay : 16'd10;
     config_data[111:96]<=captured_preset_enabled ? preset_sustain : 16'd0;
     config_data[127:112]<=captured_preset_enabled ? preset_release_coefficient : 16'd8;
     config_valid<=1;state<=3;
    end
    3:if(config_ready)begin
     config_valid<=0;state<=0;
     if(revision[current_voice]==sent_revision)dirty[current_voice]<=0;
     if(voice_event[current_voice]==sent_event && config_data[58])retrigger_pending[current_voice]<=0;
    end
   endcase
   case(alloc_state)
    0:if(event_count!=0)begin
     pending_event<=event_fifo[event_rd];alloc_scan<=0;idle_found<=0;release_found<=0;active_found<=0;
     eligible_seen<=0;fade_completed<=0;minimum_release<=65535;minimum_active<=65535;oldest<=0;alloc_state<=1;
    end
    1:begin
     if(!external_gate[alloc_scan])begin
      eligible_seen<=1;
      if(!idle_found && !gate[alloc_scan] && scan_env==0 && !retrigger_pending[alloc_scan])begin
       idle_choice<=alloc_scan;idle_found<=1;
      end
      if(!gate[alloc_scan] && !retrigger_pending[alloc_scan] && (!release_found || scan_env<=minimum_release))begin
       release_found<=1;minimum_release<=scan_env;release_choice<=alloc_scan;
      end
      if(gate[alloc_scan] && (!active_found || age[alloc_scan]>oldest ||
         (age[alloc_scan]==oldest && scan_env<=minimum_active)))begin
       active_found<=1;oldest<=age[alloc_scan];minimum_active<=scan_env;active_choice<=alloc_scan;
      end
     end
     if(alloc_scan==VOICES-1)alloc_state<=2;else alloc_scan<=alloc_scan+1'b1;
    end
    2:begin
     if(external_valid)alloc_state<=0;
     else if(!eligible_seen)alloc_state<=0;
     else begin
      chosen_voice<=idle_found ? idle_choice : release_found ? release_choice : active_choice;
      alloc_state<=4;
     end
    end
    4:begin
     if(external_valid)alloc_state<=0;
     else begin chosen_alive<=selected_alive;alloc_state<=5;end
    end
    5:begin
     if(external_valid)alloc_state<=0;
     else if(chosen_alive && !fade_completed)begin
      // Keep old frequency/wave during the eight-sample fade; commit the new
      // event only after the old envelope reaches zero and its config drains.
      gate[chosen_voice]<=0;fast_stop[chosen_voice]<=1;dirty[chosen_voice]<=1;
      revision[chosen_voice]<=revision[chosen_voice]+1'b1;
      fade_voice<=chosen_voice;stolen_notes<=stolen_notes+1'b1;alloc_state<=3;
     end else if(event_pop)begin
      owned[chosen_voice]<=1;gate[chosen_voice]<=1;dirty[chosen_voice]<=1;retrigger_pending[chosen_voice]<=1;fast_stop[chosen_voice]<=0;
      base_ftw[chosen_voice]<=note_ftw(pending_event[25:23],$signed(pending_event[22:21]));
      gain[chosen_voice]<=pending_event[20:13]>>1;voice_zone[chosen_voice]<=pending_event[25:23];
      voice_event[chosen_voice]<=pending_event[12:5];voice_preset_enabled[chosen_voice]<=pending_event[4];
      voice_preset[chosen_voice]<=pending_event[3:2];voice_release[chosen_voice]<=pending_event[1:0];
      revision[chosen_voice]<=revision[chosen_voice]+1'b1;gate_ticks[chosen_voice]<=0;age[chosen_voice]<=0;alloc_state<=0;
     end
    end
    3:begin
     if(external_valid && external_data[VOICE_BITS-1:0]==fade_voice)alloc_state<=0;
     else if(envelopes[fade_voice*16+:16]==0 && !dirty[fade_voice] &&
          !(config_valid && current_voice==fade_voice))begin fade_completed<=1;alloc_state<=5;end
    end
   endcase
   for(i=0;i<VOICES;i=i+1)if(owned[i])begin
    if(event_pop && i!=chosen_voice && age[i]!=255)age[i]<=age[i]+1'b1;
    if(gate[i])begin
     if(!enabled || gate_ticks[i]>=(voice_preset_enabled[i] && voice_preset[i]==2 ? HOLD_TICKS*4 :
        voice_preset_enabled[i] && voice_preset[i]==1 ? HOLD_TICKS*2 : HOLD_TICKS))begin
      if(!(event_pop && i==chosen_voice))begin gate[i]<=0;dirty[i]<=1;revision[i]<=revision[i]+1'b1;end
     end else if(!(event_pop && i==chosen_voice))gate_ticks[i]<=gate_ticks[i]+1'b1;
    end
    if(bend_cents!=previous_bend || vibrato_cents!=previous_vibrato)begin dirty[i]<=1;revision[i]<=revision[i]+1'b1;end
    if(velocity_update && voice_event[i]==event_id)begin gain[i]<=velocity>>1;dirty[i]<=1;revision[i]<=revision[i]+1'b1;end
   end
   if(!enabled)begin event_count<=0;event_rd<=event_wr;alloc_state<=0;end
   if(external_valid && external_data[7:0]<VOICES)begin
    owned[external_data[VOICE_BITS-1:0]]<=0;gate[external_data[VOICE_BITS-1:0]]<=0;
    external_gate[external_data[VOICE_BITS-1:0]]<=external_data[56];
    dirty[external_data[VOICE_BITS-1:0]]<=0;retrigger_pending[external_data[VOICE_BITS-1:0]]<=0;fast_stop[external_data[VOICE_BITS-1:0]]<=0;
    if(current_voice==external_data[VOICE_BITS-1:0] && state!=0)begin state<=0;config_valid<=0;end
   end
  end
 end
endmodule
