// Derived from fpga/rtl/audio_core.v: per-Voice brightness and idle-only config acceptance.
// Independent Voice states with a shared sample scheduler (4 or 32 Voices).
// Every Voice is loaded into scalar pipeline registers before arithmetic.
// Preset config: bit55 enable, bits51:50 tone, bits53:52 tail.
module dual_audio_core #(parameter VOICES=4,parameter MASTER_SHIFT=0,
 parameter VOICE_BITS=$clog2(VOICES),parameter ENABLE_EXPRESSION=0,parameter FOUR_TIMBRES_ONLY=1)(input clk,input rst_n,input sample_tick,input config_valid,input [127:0] config_data,
 output reg [79:0] samples,output reg sample_valid,output reg [31:0] clips,
 input[VOICES-1:0]wrist_hold,
  input [VOICES*8-1:0] local_brightness,input[VOICES*7-1:0]all_notes,input[63:0]hold_samples,output reg[VOICES-1:0]release_due,
output config_ready,output [63:0] envelopes,
 output [VOICES*16-1:0] all_envelopes,output reg [VOICES*16-1:0] voice_samples,
 output [VOICES-1:0] active_voices,output reg [31:0] underflows,
 output reg [15:0] last_render_cycles,max_render_cycles,
 input[47:0]glide_coefficients,input[39:0]vibrato_ratios,
 input [1:0]piano_hold,input[31:0]piano_coefficients,
 input [VOICE_BITS-1:0] monitor_voice,output [31:0] monitor_frequency,
 output [15:0] monitor_envelope,output [1:0] monitor_stage,
 output reg signed [15:0] stereo_left,stereo_right,output reg[31:0] stereo_clips);
 // Dynamic snapshot/writeback and configuration updates require register
 // semantics. Avoid Gowin inferring unsupported read-before-write RAM modes.
 reg [31:0] phase[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [VOICES-1:0]render_select;
 reg [31:0] freq[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] mod_phase[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] mod_freq[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [7:0] gain[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [1:0] wave[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [2:0] preset[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 // Same dynamic snapshot/writeback semantics as the other per-voice state.
 // GW5AST cannot place an SP with inferred READ_BEFORE_WRITE (WRITE_MODE=10).
 reg[23:0]piano_body[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg[23:0]piano_fraction[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [1:0] tail[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg gate[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg old_gate[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg local_voice[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg retrigger[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg preset_mode[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [15:0] env[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [15:0] attack[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [15:0] decay[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [15:0] sustain[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [15:0] release_step[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [15:0] index_env[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [17:0] release_count[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] release_level[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [1:0] stage[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg fast_release[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg[VOICE_BITS-1:0] voice;
 // Public maximum is 10 s at48kHz =480000 samples, fitting19 bits.
 reg[18:0]hold_remaining[0:VOICES-1],hold_snapshot[0:VOICES-1];
 reg[18:0]v_remaining;
 wire model_done;wire signed[15:0]model_value;

 reg[31:0]pitch_start[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg[31:0]pitch_target[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg[23:0]pitch_position[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg[31:0]last_pitch[0:1];reg[1:0]last_pitch_valid;
 reg[31:0]v_pitch_start,v_pitch_target;reg[23:0]v_pitch_position;
 reg[VOICES-1:0]wrist_mode;
   wire[23:0]glide_step=wrist_mode[voice] ? 24'd69906 : ENABLE_EXPRESSION ? glide_coefficients[(voice>=VOICES/2)*24+:24] : 24'd0;
 wire[24:0]next_position={1'b0,v_pitch_position}+{1'b0,glide_step};
 wire signed[32:0]pitch_distance=$signed({1'b0,v_pitch_target})-$signed({1'b0,v_pitch_start});
 reg signed[57:0]glide_product;reg[51:0]vibrato_product;
 wire signed[57:0]interpolated_pitch=$signed({1'b0,v_pitch_start})+(glide_product>>>24);
 wire[19:0]vibrato_ratio=ENABLE_EXPRESSION ? vibrato_ratios[(voice>=VOICES/2)*20+:20] : 20'd65536;
 reg v_trigger;integer i;
 reg [4:0] state;
 reg [31:0] v_phase,v_freq,v_mod_phase,v_mod_freq,v_release_level;
 reg [7:0] v_gain,v_brightness;reg [2:0]v_preset;reg [1:0] v_wave,v_tail,v_stage;
 reg[23:0]v_body,v_fraction;reg[15:0]v_piano_coefficient;reg v_piano_hold;
 reg[39:0]body_product;reg signed[43:0]body_wave_product;
 reg signed[37:0]brightness_product;reg signed[18:0]piano_fundamental,piano_harmonics;
 reg signed[15:0]piano_second,piano_third;reg signed[18:0]piano_composite;
 wire[24:0]fraction_sum={1'b0,body_product[23:0]}+{1'b0,v_fraction};
 wire[16:0]body_delta={1'b0,body_product[39:24]}+{16'b0,fraction_sum[24]};
 wire [15:0] blend_gain;reg signed [32:0] wave_gain_product;
 assign config_ready=state==0 && !sample_tick;
 wire signed [15:0] sine,modulator,carrier,dark_wave,bright_wave;
 reg [31:0] carrier_phase;
 sine_lut lut(.addr(v_phase[31:22]),.value(sine));
 sine_lut mod_lut(.addr(v_mod_phase[31:22]),.value(modulator));
 sine_lut carrier_lut(.addr(carrier_phase[31:22]),.value(carrier));
 wire[31:0]piano_phase=state==16 ? v_phase<<1 : state==17 ? v_phase+(v_phase<<1) : v_phase<<2;
 wire signed[15:0]piano_sine;
 sine_lut piano_lut(.addr(piano_phase[31:22]),.value(piano_sine));
 generate if(!FOUR_TIMBRES_ONLY)begin: legacy_tables
 instrument_waves waves(.clk(clk),.phase(v_phase),.frequency(v_freq),
   .bass(v_preset==1),.brightness(v_brightness),.dark(dark_wave),.bright(bright_wave),.blend_gain(blend_gain));
 end else begin: four_only_tables
 assign dark_wave=16'sd0;assign bright_wave=16'sd0;assign blend_gain=16'hffff;
 end endgenerate
 reg v_gate,v_old_gate,v_local_voice,v_retrigger,v_preset_mode,v_fast_release;
 reg [15:0] v_env,v_attack,v_decay,v_sustain,v_release_step,v_index_env;
 reg [17:0] v_release_count;
 reg [15:0] render_cycles;
 reg signed [23:0] sum;
 wire signed [23:0] scaled_sum=$signed(sum)>>>MASTER_SHIFT;
 // Voices 0..BANK-1 belong to hand 0; the remaining bank belongs to hand 1.
 // Keep legacy mono monitoring, but never obtain stereo by duplicating it.
 reg signed [23:0]sum_left,sum_right;
 wire signed [23:0]scaled_left=sum_left>>>MASTER_SHIFT,scaled_right=sum_right>>>MASTER_SHIFT;
 wire clip_left=scaled_left>32767 || scaled_left< -32768;
 wire clip_right=scaled_right>32767 || scaled_right< -32768;
 assign monitor_frequency=freq[monitor_voice];assign monitor_envelope=env[monitor_voice];
 assign monitor_stage=!gate[monitor_voice] && env[monitor_voice]!=0 ? 2'd3 : stage[monitor_voice];
 reg signed [15:0] osc,oscillator_sample,modulator_sample;
 reg signed [32:0] prod1,mod_product;reg signed [41:0] prod2;
 reg signed [15:0] voice_value;
 reg signed [25:0] blend_dark,blend_bright;
 reg [25:0] depth_product;reg [15:0] fm_depth;
 reg [31:0] release_source;reg [47:0] release_product;
 wire [31:0] release_delta=release_product[47:16]==0 ? 32'd1 : release_product[47:16];
 reg[31:0]release_delta_q,release_next_q;reg release_exhausted_q;
 wire [17:0] release_limit=v_tail==0 ? 18'd9600 : v_tail==1 ? 18'd24000 : 18'd72000;
 wire fm_voice=v_preset_mode && (v_preset==2 || v_preset==3);
 wire signed [15:0] saw={~v_phase[31],v_phase[30:16]};
 wire [15:0] fm_limit;
 wire [15:0] requested_fm_depth=depth_product[25:8]>65535 ? 16'hffff : depth_product[23:8];
 generate if(!FOUR_TIMBRES_ONLY)begin: legacy_limits
 fm_limits bandwidth(.clk(clk),.frequency(v_freq),.bell(v_preset==3),.limit(fm_limit));
 end else begin: four_only_limits
 assign fm_limit=16'd0;
 end endgenerate
 genvar ei;
 generate for(ei=0;ei<4;ei=ei+1) begin: envelope_bus
  assign envelopes[ei*16+:16]=env[ei];
 end endgenerate
 generate for(ei=0;ei<VOICES;ei=ei+1)begin: all_voice_bus
  assign all_envelopes[ei*16+:16]=env[ei];
  assign active_voices[ei]=(gate[ei] || env[ei]!=0) && gain[ei]!=0;
 end endgenerate
 always @*begin
  case(v_wave)
   0:osc=sine;
   1:osc=saw;
   2:osc=v_phase[31]?-16'sd32767:16'sd32767;
   3:osc=v_phase[31]?16'sd32767-$signed({1'b0,v_phase[30:16]})*2:-16'sd32767+$signed({1'b0,v_phase[30:16]})*2;
  endcase
 end
 four_timbres #(.VOICES(VOICES)) models(.clk(clk),.rst_n(rst_n),.start(state==2 && v_preset_mode && v_preset<4),.trigger(v_trigger),.hold_body(v_piano_hold && v_gate),.voice(voice),.kind(v_preset[1:0]),.note(all_notes[voice*7+:7]),.phase(v_phase),.frequency(v_freq),.velocity(v_gain),.brightness(v_brightness),.decay_coefficient(v_piano_coefficient),.done(model_done),.value(model_value));
 always @(posedge clk)begin
  if(!rst_n)begin
   render_select<=0;wrist_mode<=0;release_due<=0;state<=0;voice<=0;sum<=0;sum_left<=0;sum_right<=0;stereo_left<=0;stereo_right<=0;stereo_clips<=0;
   samples<=0;sample_valid<=0;clips<=0;prod1<=0;prod2<=0;voice_value<=0;
   blend_dark<=0;blend_bright<=0;oscillator_sample<=0;modulator_sample<=0;depth_product<=0;fm_depth<=0;
   mod_product<=0;carrier_phase<=0;release_product<=0;release_source<=0;v_trigger<=0;
   release_delta_q<=1;release_next_q<=0;release_exhausted_q<=0;
   voice_samples<=0;underflows<=0;last_render_cycles<=0;max_render_cycles<=0;render_cycles<=0;
   v_fast_release<=0;
   v_body<=0;v_fraction<=0;v_piano_coefficient<=134;v_piano_hold<=0;body_product<=0;body_wave_product<=0;
   brightness_product<=0;piano_fundamental<=0;piano_harmonics<=0;piano_second<=0;piano_third<=0;piano_composite<=0;
   v_pitch_start<=0;v_pitch_target<=0;v_pitch_position<=0;glide_product<=0;vibrato_product<=0;last_pitch[0]<=0;last_pitch[1]<=0;last_pitch_valid<=0;
   v_phase<=0;
   v_freq<=0;
   v_mod_phase<=0;
   v_mod_freq<=0;
   v_gain<=0;
   v_brightness<=0;wave_gain_product<=0;
   v_wave<=0;
   v_preset<=0;
   v_tail<=0;
   v_gate<=0;
   v_old_gate<=0;
   v_local_voice<=0;
   v_retrigger<=0;
   v_preset_mode<=0;
   v_env<=0;
   v_attack<=0;
   v_decay<=0;
   v_sustain<=0;
   v_release_step<=0;
   v_index_env<=0;
   v_release_count<=0;
   v_release_level<=0;
   v_stage<=0;
   for(i=0;i<VOICES;i=i+1)begin
    pitch_start[i]<=0;pitch_target[i]<=0;pitch_position[i]<=0;fast_release[i]<=0;phase[i]<=0;freq[i]<=i<4 ? 32'd33554432*(i+1) : 32'd0;mod_phase[i]<=0;mod_freq[i]<=0;
    gain[i]<=46;wave[i]<=0;gate[i]<=0;old_gate[i]<=0;local_voice[i]<=0;retrigger[i]<=0;
    hold_remaining[i]<=0;hold_snapshot[i]<=48000;env[i]<=0;attack[i]<=137;decay[i]<=17;sustain[i]<=45874;release_step[i]<=8;stage[i]<=0;
    preset[i]<=0;tail[i]<=0;preset_mode[i]<=0;index_env[i]<=0;release_count[i]<=0;release_level[i]<=0;piano_body[i]<=0;piano_fraction[i]<=0;
   end
  end else begin
   // The four production timbres already wait for the model renderer. Use
   // that time to split minimum-step decode and 32-bit release subtraction,
   // avoiding the routed 25-level release_product -> envelope-DSP path.
   release_delta_q<=release_delta;
   release_next_q<=release_source-release_delta_q;
   release_exhausted_q<=(release_source<=release_delta_q);
   sample_valid<=0;release_due<=0;
   if(ENABLE_EXPRESSION && active_voices==0)last_pitch_valid<=0;
   if(sample_tick && state!=0)underflows<=underflows+1'b1;
   if(sample_tick && state==0)render_cycles<=0;
   else if(state!=0)render_cycles<=render_cycles+1'b1;
   case(state)
    0:if(sample_tick)begin
     voice<=0;sum<=0;sum_left<=0;sum_right<=0;state<=12;
    end
    12:begin
     render_select<=({{(VOICES-1){1'b0}},1'b1}<<voice);
     v_fast_release<=fast_release[voice];
     v_pitch_start<=pitch_start[voice];v_pitch_target<=pitch_target[voice];v_pitch_position<=pitch_position[voice];
     v_phase<=phase[voice];
     v_freq<=freq[voice];
     v_mod_phase<=mod_phase[voice];
     v_mod_freq<=mod_freq[voice];
     v_remaining<=hold_remaining[voice];v_gain<=gain[voice];
     v_brightness<=local_brightness[voice*8+:8];
     v_wave<=wave[voice];
     v_preset<=FOUR_TIMBRES_ONLY ? {1'b0,preset[voice][1:0]} : preset[voice];
     v_tail<=tail[voice];
     v_gate<=gate[voice];
     v_old_gate<=old_gate[voice];
     v_local_voice<=local_voice[voice];
     v_retrigger<=retrigger[voice];
     v_preset_mode<=FOUR_TIMBRES_ONLY ? 1'b1 : preset_mode[voice];
     v_env<=env[voice];
     v_attack<=attack[voice];
     v_decay<=decay[voice];
     v_sustain<=sustain[voice];
     v_release_step<=release_step[voice];
     v_index_env<=index_env[voice];
     v_release_count<=release_count[voice];
     v_release_level<=release_level[voice];
     v_stage<=stage[voice];
     v_body<=piano_body[voice];v_fraction<=piano_fraction[voice];
     v_piano_hold<=piano_hold[voice>=VOICES/2];v_piano_coefficient<=piano_coefficients[(voice>=VOICES/2)*16+:16];
     state<=ENABLE_EXPRESSION ? 23 : 13;
    end
    23:begin
     if(glide_step==0 || v_pitch_position==24'hffffff || next_position[24])begin
      v_pitch_position<=24'hffffff;v_freq<=v_pitch_target;for(integer fw=0;fw<VOICES;fw=fw+1)if(render_select[fw])freq[fw]<=v_pitch_target;state<=25;
     end else begin
      v_pitch_position<=next_position[23:0];glide_product<=pitch_distance*$signed({1'b0,next_position[23:0]});state<=24;
     end
    end
    24:begin v_freq<=interpolated_pitch[31:0];for(integer fw=0;fw<VOICES;fw=fw+1)if(render_select[fw])freq[fw]<=interpolated_pitch[31:0];state<=25;end
    25:begin vibrato_product<=v_freq*vibrato_ratio;pitch_position[voice]<=v_pitch_position;state<=26;end
    26:begin
     v_freq<=vibrato_product[47:16];
     v_mod_freq<=v_preset==3 ? vibrato_product[47:16]*32'd3 : vibrato_product[47:16]<<1;state<=13;
    end
    13:begin
     v_phase<=v_phase+v_freq;v_mod_phase<=v_mod_phase+v_mod_freq;
     phase[voice]<=v_phase+v_freq;mod_phase[voice]<=v_mod_phase+v_mod_freq;
     old_gate[voice]<=v_gate;retrigger[voice]<=0;
     v_trigger<=v_retrigger || (v_gate && !v_old_gate);
     if(v_retrigger || (v_gate && !v_old_gate))begin
      hold_remaining[voice]<=hold_snapshot[voice]>0 ? hold_snapshot[voice]-1'b1 : 0;
     end else if(v_gate && !(wrist_hold[voice]===1'b1))begin
      if(v_remaining==0)begin v_gate<=0;gate[voice]<=0;release_due[voice]<=1;end
      else hold_remaining[voice]<=v_remaining-1'b1;
     end
     if(!v_gate && v_env==0 && !v_retrigger)begin voice_value<=0;state<=10;end
     else state<=1;
    end
    1:begin
     release_source<=v_release_count==0 ? {v_env,16'd0} : v_release_level;
     modulator_sample<=modulator;
     if(v_trigger)begin
      v_body<=24'hffffff;v_fraction<=0;
      v_stage<=0;v_env<=0;v_release_count<=0;v_release_level<=0;
      v_index_env<=v_preset==2 ? 16'd12000 : v_preset==4 ? 16'd65535 : 16'd50000;
     end else begin
      if(v_gate)begin
       v_release_count<=0;
       case(v_stage)
        0:if({1'b0,v_env}+{1'b0,v_attack}>=65535)begin v_env<=65535;v_stage<=1;end
          else v_env<=v_env+v_attack;
        1:if(v_env<={1'b0,v_sustain}+{1'b0,v_decay})begin v_env<=v_sustain;v_stage<=2;end
          else v_env<=v_env-v_decay;
        default:v_env<=v_sustain;
       endcase
      end else if(v_fast_release)begin
       v_env<=v_env<=256 ? 0 : v_env-256;
      end else if(!v_preset_mode)begin
       if(v_env<=v_release_step)v_env<=0;else v_env<=v_env-v_release_step;
      end
      if(v_index_env!=0)begin
       if(v_preset==2 && v_gate)begin
        if(v_index_env>5024)v_index_env<=v_index_env-24;else v_index_env<=5000;
       end else if(v_preset==4)begin
        if(v_index_env>16387)v_index_env<=v_index_env-3;else v_index_env<=16384;
       end
       else if(v_index_env>40)v_index_env<=v_index_env-40;
       else v_index_env<=0;
      end
     end
     state<=2;
    end
    2:begin
     release_product<=release_source*v_release_step;
     if(v_preset_mode && v_preset==4)body_product<=v_body*v_piano_coefficient;
     else if(v_preset_mode && v_preset==5)oscillator_sample<=sine;
     else if(fm_voice)begin
      depth_product<=v_index_env*({1'b0,v_brightness}+9'd64);
     end else if(v_preset_mode || v_local_voice)begin
      blend_dark<=(v_preset_mode ? dark_wave : osc)*$signed(10'd256-{2'b0,v_brightness});
      blend_bright<=(v_preset_mode ? bright_wave : saw)*$signed({2'b0,v_brightness});
     end else oscillator_sample<=osc;
     state<=v_preset_mode && v_preset<4 ? 27 : 28;
    end
    // Generic legacy waveforms have no model wait; preserve release arithmetic
    // with two explicit clocks. The four production timbres add no render cycle.
    28:state<=29;
    29:state<=3;
    27:if(model_done)begin oscillator_sample<=model_value;state<=3;end
    3:begin
     // Preserve 16 fractional bits; a minimum whole-envelope step would make
     // long quiet tails end prematurely. The selected duration remains bounded.
     if(v_preset_mode && !v_gate && !v_trigger && !v_fast_release && v_env!=0)begin
      if(v_env<=32 || release_exhausted_q || v_release_count>=release_limit-1)begin
       v_env<=0;v_release_level<=0;
      end else begin
       v_env<=release_next_q[31:16];v_release_level<=release_next_q;
       v_release_count<=v_release_count+1'b1;
      end
     end
     if(v_preset_mode && v_preset<4)state<=7;
     else if(v_preset_mode && v_preset==4)state<=16;
     else if(v_preset_mode && v_preset==5)state<=7;
     else if(fm_voice)begin fm_depth<=requested_fm_depth>fm_limit ? fm_limit : requested_fm_depth;state<=4;end
     else begin
      if(v_preset_mode || v_local_voice)oscillator_sample<=($signed(blend_dark)+$signed(blend_bright))>>>8;
      state<=v_preset_mode ? 14 : 7;
     end
    end
    4:begin mod_product<=modulator_sample*$signed({1'b0,fm_depth});state<=5;end
    5:begin carrier_phase<=v_phase+mod_product[31:0];state<=6;end
    6:begin oscillator_sample<=($signed({carrier[15],carrier})>>>1)+($signed({sine[15],sine})>>>1);state<=7;end
    14:begin wave_gain_product<=oscillator_sample*$signed({1'b0,blend_gain});state<=15;end
    15:begin oscillator_sample<=wave_gain_product>>>12;state<=7;end
    16:begin
     piano_fundamental<=($signed({{3{sine[15]}},sine})*19'sd5)>>>3;
     piano_second<=v_freq<32'h40000000 ? piano_sine : 0;
     if(v_piano_hold && v_gate)begin v_body<=24'hffffff;v_fraction<=0;end
     else if(v_body>body_delta)begin v_body<=v_body-body_delta;v_fraction<=fraction_sum[23:0];end
     else begin v_body<=0;v_fraction<=0;end
     state<=17;
    end
    17:begin piano_third<=v_freq<32'h2aaaaaaa ? piano_sine : 0;state<=18;end
    18:begin piano_harmonics<=($signed({{3{piano_second[15]}},piano_second})>>>2)+($signed({{3{piano_third[15]}},piano_third})>>>3)+(v_freq<32'h20000000 ? ($signed({{3{piano_sine[15]}},piano_sine})>>>4) : 19'sd0);state<=19;end
    19:begin brightness_product<=piano_harmonics*$signed({1'b0,v_index_env});state<=20;end
    20:begin piano_composite<=piano_fundamental+(brightness_product>>>16);state<=21;end
    21:begin body_wave_product<=piano_composite*$signed({1'b0,v_body});state<=22;end
    22:begin
     if((body_wave_product>>>24)>32767)oscillator_sample<=32767;
     else if((body_wave_product>>>24)< -32768)oscillator_sample<=-32768;
     else oscillator_sample<=body_wave_product[39:24];state<=7;
    end
    7:begin prod1<=oscillator_sample*$signed({1'b0,v_env});state<=8;end
    8:begin prod2<=prod1*$signed({1'b0,v_gain});state<=9;end
    9:begin voice_value<=prod2[39:24]+{15'b0,(prod2[23] && (!prod2[41] || |prod2[22:0]))};state<=10;end
    10:begin
     voice_samples[voice*16+:16]<=voice_value;
     if(voice<4)samples[voice*16+:16]<=voice_value;
     sum<=sum+voice_value;
     if(voice<VOICES/2)sum_left<=sum_left+voice_value;else sum_right<=sum_right+voice_value;
     env[voice]<=v_env;stage[voice]<=v_stage;index_env[voice]<=v_index_env;
     piano_body[voice]<=v_body;piano_fraction[voice]<=v_fraction;
     release_count[voice]<=v_release_count;release_level[voice]<=v_release_level;
     if(voice==VOICES-1)state<=11;else begin voice<=voice+1;state<=12;end
    end
    11:begin
     stereo_left<=clip_left ? (scaled_left<0 ? 16'sh8000 : 16'sh7fff) : scaled_left[15:0];
     stereo_right<=clip_right ? (scaled_right<0 ? 16'sh8000 : 16'sh7fff) : scaled_right[15:0];
     if((clip_left || clip_right) && stereo_clips!=32'hffffffff)stereo_clips<=stereo_clips+1'b1;
     if(scaled_sum>32767)begin samples[79:64]<=32767;clips<=clips+1;end
     else if(scaled_sum< -32768)begin samples[79:64]<=16'h8000;clips<=clips+1;end
     else samples[79:64]<=scaled_sum[15:0];
     last_render_cycles<=render_cycles+1'b1;
     if(render_cycles+1'b1>max_render_cycles)max_render_cycles<=render_cycles+1'b1;
     sample_valid<=1;state<=0;
    end
   endcase
   // Configuration wins over clearing a retrigger on the same sample tick.
   // Constant-index bank-local comparisons remove the configuration-address
   // -> 32:1 frequency mux -> compare -> pitch_start data path. Hand selection
   // also becomes a compile-time constant; ready/valid latency is unchanged.
   for(integer cv=0;cv<VOICES;cv=cv+1)if(config_valid && config_data[7:0]==cv)begin
    wrist_mode[cv]<=config_data[61];
    fast_release[cv]<=config_data[59];
    freq[cv]<=config_data[39:8];
    pitch_target[cv]<=config_data[39:8];
    if(config_data[58] && config_data[56])begin
     hold_snapshot[cv]<=hold_samples[(cv>=VOICES/2)*32+:19];
     last_pitch[cv>=VOICES/2]<=config_data[39:8];last_pitch_valid[cv>=VOICES/2]<=1;
     pitch_position[cv]<=24'hffffff;
     if(ENABLE_EXPRESSION && glide_coefficients[(cv>=VOICES/2)*24+:24]!=0 && last_pitch_valid[cv>=VOICES/2])begin
      pitch_start[cv]<=last_pitch[cv>=VOICES/2];
      freq[cv]<=last_pitch[cv>=VOICES/2];pitch_position[cv]<=0;
     end else pitch_start[cv]<=config_data[39:8];
    end else if(config_data[61] && config_data[39:8]!=pitch_target[cv])begin
     pitch_start[cv]<=freq[cv];pitch_position[cv]<=0;
    end
    gain[cv]<=config_data[47:40];
    wave[cv]<=config_data[49:48];gate[cv]<=config_data[56] && (config_data[58] || (wrist_hold[cv]===1'b1) || hold_remaining[cv]!=0);
    local_voice[cv]<=config_data[57];
    if(config_data[58])retrigger[cv]<=1;
    preset_mode[cv]<=FOUR_TIMBRES_ONLY ? 1'b1 : config_data[55];preset[cv]<={FOUR_TIMBRES_ONLY ? 1'b0 : config_data[60],config_data[51:50]};tail[cv]<=config_data[53:52];
    if(config_data[51:50]==3)mod_freq[cv]<=config_data[39:8]*3;
    else mod_freq[cv]<=config_data[39:8]<<1;
    attack[cv]<=config_data[79:64];decay[cv]<=config_data[95:80];
    sustain[cv]<=config_data[111:96];release_step[cv]<=config_data[127:112];
   end
  end
 end
endmodule


