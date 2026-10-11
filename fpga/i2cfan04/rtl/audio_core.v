// Independent Voice states with a shared sample scheduler (4 or 32 Voices).
// Every Voice is loaded into scalar pipeline registers before arithmetic.
// Preset config: bit55 enable, bits51:50 tone, bits53:52 tail.
module audio_core #(parameter VOICES=4,parameter MASTER_SHIFT=0,
 parameter VOICE_BITS=$clog2(VOICES))(input clk,input rst_n,input sample_tick,input config_valid,input [127:0] config_data,
 output reg [79:0] samples,output reg sample_valid,output reg [31:0] clips,
 input [7:0] local_brightness,output [63:0] envelopes,
 output [VOICES*16-1:0] all_envelopes,output reg [VOICES*16-1:0] voice_samples,
 output [VOICES-1:0] active_voices,output reg [31:0] underflows,
 output reg [15:0] last_render_cycles,max_render_cycles,
 input [VOICE_BITS-1:0] monitor_voice,output [31:0] monitor_frequency,
 output [15:0] monitor_envelope,output [1:0] monitor_stage);
 // Dynamic snapshot/writeback and configuration updates require register
 // semantics. Avoid Gowin inferring unsupported read-before-write RAM modes.
 reg [31:0] phase[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] freq[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] mod_phase[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] mod_freq[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [7:0] gain[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [1:0] wave[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg [1:0] preset[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
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
 reg v_trigger;integer i;
 reg [3:0] state;reg [VOICE_BITS-1:0] voice;
 wire signed [15:0] sine,modulator,carrier,dark_wave,bright_wave;
 reg [31:0] carrier_phase;
 sine_lut lut(.addr(v_phase[31:24]),.value(sine));
 sine_lut mod_lut(.addr(v_mod_phase[31:24]),.value(modulator));
 sine_lut carrier_lut(.addr(carrier_phase[31:24]),.value(carrier));
 instrument_waves waves(.clk(clk),.phase(v_phase),.frequency(v_freq),
   .bass(v_preset==1),.brightness(v_brightness),.dark(dark_wave),.bright(bright_wave),.blend_gain(blend_gain));
 reg [31:0] v_phase,v_freq,v_mod_phase,v_mod_freq,v_release_level;
 reg [7:0] v_gain,v_brightness;reg [1:0] v_wave,v_preset,v_tail,v_stage;
 wire [15:0] blend_gain;reg signed [32:0] wave_gain_product;
 reg v_gate,v_old_gate,v_local_voice,v_retrigger,v_preset_mode,v_fast_release;
 reg [15:0] v_env,v_attack,v_decay,v_sustain,v_release_step,v_index_env;
 reg [17:0] v_release_count;
 reg [15:0] render_cycles;
 wire signed [23:0] scaled_sum=$signed(sum)>>>MASTER_SHIFT;
 assign monitor_frequency=freq[monitor_voice];assign monitor_envelope=env[monitor_voice];
 assign monitor_stage=!gate[monitor_voice] && env[monitor_voice]!=0 ? 2'd3 : stage[monitor_voice];
 reg signed [15:0] osc,oscillator_sample,modulator_sample;
 reg signed [32:0] prod1,mod_product;reg signed [41:0] prod2;
 reg signed [23:0] sum;reg signed [15:0] voice_value;
 reg signed [25:0] blend_dark,blend_bright;
 reg [25:0] depth_product;reg [15:0] fm_depth;
 reg [31:0] release_source;reg [47:0] release_product;
 wire [31:0] release_delta=release_product[47:16]==0 ? 32'd1 : release_product[47:16];
 wire [31:0] release_next=release_source-release_delta;
 wire [17:0] release_limit=v_tail==0 ? 18'd9600 : v_tail==1 ? 18'd24000 : 18'd72000;
 wire fm_voice=v_preset_mode && v_preset>=2;
 wire signed [15:0] saw={~v_phase[31],v_phase[30:16]};
 wire [15:0] fm_limit;
 wire [15:0] requested_fm_depth=depth_product[25:8]>65535 ? 16'hffff : depth_product[23:8];
 fm_limits bandwidth(.clk(clk),.frequency(v_freq),.bell(v_preset==3),.limit(fm_limit));
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
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;voice<=0;sum<=0;samples<=0;sample_valid<=0;clips<=0;prod1<=0;prod2<=0;voice_value<=0;
   blend_dark<=0;blend_bright<=0;oscillator_sample<=0;modulator_sample<=0;depth_product<=0;fm_depth<=0;
   mod_product<=0;carrier_phase<=0;release_product<=0;release_source<=0;v_trigger<=0;
   voice_samples<=0;underflows<=0;last_render_cycles<=0;max_render_cycles<=0;render_cycles<=0;
   v_fast_release<=0;
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
    fast_release[i]<=0;phase[i]<=0;freq[i]<=i<4 ? 32'd33554432*(i+1) : 32'd0;mod_phase[i]<=0;mod_freq[i]<=0;
    gain[i]<=46;wave[i]<=0;gate[i]<=0;old_gate[i]<=0;local_voice[i]<=0;retrigger[i]<=0;
    env[i]<=0;attack[i]<=137;decay[i]<=17;sustain[i]<=45874;release_step[i]<=8;stage[i]<=0;
    preset[i]<=0;tail[i]<=0;preset_mode[i]<=0;index_env[i]<=0;release_count[i]<=0;release_level[i]<=0;
   end
  end else begin
   sample_valid<=0;
   if(sample_tick && state!=0)underflows<=underflows+1'b1;
   if(sample_tick && state==0)render_cycles<=0;
   else if(state!=0)render_cycles<=render_cycles+1'b1;
   case(state)
    0:if(sample_tick)begin
     voice<=0;sum<=0;state<=12;
    end
    12:begin
     v_fast_release<=fast_release[voice];
     v_phase<=phase[voice];
     v_freq<=freq[voice];
     v_mod_phase<=mod_phase[voice];
     v_mod_freq<=mod_freq[voice];
     v_gain<=gain[voice];
     v_brightness<=local_brightness;
     v_wave<=wave[voice];
     v_preset<=preset[voice];
     v_tail<=tail[voice];
     v_gate<=gate[voice];
     v_old_gate<=old_gate[voice];
     v_local_voice<=local_voice[voice];
     v_retrigger<=retrigger[voice];
     v_preset_mode<=preset_mode[voice];
     v_env<=env[voice];
     v_attack<=attack[voice];
     v_decay<=decay[voice];
     v_sustain<=sustain[voice];
     v_release_step<=release_step[voice];
     v_index_env<=index_env[voice];
     v_release_count<=release_count[voice];
     v_release_level<=release_level[voice];
     v_stage<=stage[voice];
     state<=13;
    end
    13:begin
     v_phase<=v_phase+v_freq;v_mod_phase<=v_mod_phase+v_mod_freq;
     phase[voice]<=v_phase+v_freq;mod_phase[voice]<=v_mod_phase+v_mod_freq;
     old_gate[voice]<=v_gate;retrigger[voice]<=0;
     v_trigger<=v_retrigger || (v_gate && !v_old_gate);
     if(!v_gate && v_env==0 && !v_retrigger)begin voice_value<=0;state<=10;end
     else state<=1;
    end
    1:begin
     release_source<=v_release_count==0 ? {v_env,16'd0} : v_release_level;
     modulator_sample<=modulator;
     if(v_trigger)begin
      v_stage<=0;v_env<=0;v_release_count<=0;v_release_level<=0;
      v_index_env<=v_preset==2 ? 16'd12000 : 16'd50000;
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
       v_env<=v_env<=8192 ? 0 : v_env-8192;
      end else if(!v_preset_mode)begin
       if(v_env<=v_release_step)v_env<=0;else v_env<=v_env-v_release_step;
      end
      if(v_index_env!=0)begin
       if(v_preset==2 && v_gate)begin
        if(v_index_env>5024)v_index_env<=v_index_env-24;else v_index_env<=5000;
       end else if(v_index_env>40)v_index_env<=v_index_env-40;
       else v_index_env<=0;
      end
     end
     state<=2;
    end
    2:begin
     release_product<=release_source*v_release_step;
     if(fm_voice)begin
      depth_product<=v_index_env*({1'b0,v_brightness}+9'd64);
     end else if(v_preset_mode || v_local_voice)begin
      blend_dark<=(v_preset_mode ? dark_wave : osc)*$signed(10'd256-{2'b0,v_brightness});
      blend_bright<=(v_preset_mode ? bright_wave : saw)*$signed({2'b0,v_brightness});
     end else oscillator_sample<=osc;
     state<=3;
    end
    3:begin
     // Preserve 16 fractional bits; a minimum whole-envelope step would make
     // long quiet tails end prematurely. The selected duration remains bounded.
     if(v_preset_mode && !v_gate && !v_trigger && !v_fast_release && v_env!=0)begin
      if(v_env<=32 || release_source<=release_delta || v_release_count>=release_limit-1)begin
       v_env<=0;v_release_level<=0;
      end else begin
       v_env<=release_next[31:16];v_release_level<=release_next;
       v_release_count<=v_release_count+1'b1;
      end
     end
     if(fm_voice)begin fm_depth<=requested_fm_depth>fm_limit ? fm_limit : requested_fm_depth;state<=4;end
     else begin
      if(v_preset_mode || v_local_voice)oscillator_sample<=($signed(blend_dark)+$signed(blend_bright))>>>8;
      state<=v_preset_mode ? 14 : 7;
     end
    end
    4:begin mod_product<=modulator_sample*$signed({1'b0,fm_depth});state<=5;end
    5:begin carrier_phase<=v_phase+mod_product[31:0];state<=6;end
    6:begin oscillator_sample<=carrier;state<=7;end
    14:begin wave_gain_product<=oscillator_sample*$signed({1'b0,blend_gain});state<=15;end
    15:begin oscillator_sample<=wave_gain_product>>>12;state<=7;end
    7:begin prod1<=oscillator_sample*$signed({1'b0,v_env});state<=8;end
    8:begin prod2<=prod1*$signed({1'b0,v_gain});state<=9;end
    9:begin voice_value<=prod2>>>24;state<=10;end
    10:begin
     voice_samples[voice*16+:16]<=voice_value;
     if(voice<4)samples[voice*16+:16]<=voice_value;
     sum<=sum+voice_value;
     env[voice]<=v_env;stage[voice]<=v_stage;index_env[voice]<=v_index_env;
     release_count[voice]<=v_release_count;release_level[voice]<=v_release_level;
     if(voice==VOICES-1)state<=11;else begin voice<=voice+1;state<=12;end
    end
    11:begin
     if(scaled_sum>32767)begin samples[79:64]<=32767;clips<=clips+1;end
     else if(scaled_sum< -32768)begin samples[79:64]<=16'h8000;clips<=clips+1;end
     else samples[79:64]<=scaled_sum[15:0];
     last_render_cycles<=render_cycles+1'b1;
     if(render_cycles+1'b1>max_render_cycles)max_render_cycles<=render_cycles+1'b1;
     sample_valid<=1;state<=0;
    end
   endcase
   // Configuration wins over clearing a retrigger on the same sample tick.
   if(config_valid && config_data[7:0]<VOICES)begin
    fast_release[config_data[VOICE_BITS-1:0]]<=config_data[59];
    freq[config_data[VOICE_BITS-1:0]]<=config_data[39:8];gain[config_data[VOICE_BITS-1:0]]<=config_data[47:40];
    wave[config_data[VOICE_BITS-1:0]]<=config_data[49:48];gate[config_data[VOICE_BITS-1:0]]<=config_data[56];
    local_voice[config_data[VOICE_BITS-1:0]]<=config_data[57];
    if(config_data[58])retrigger[config_data[VOICE_BITS-1:0]]<=1;
    preset_mode[config_data[VOICE_BITS-1:0]]<=config_data[55];preset[config_data[VOICE_BITS-1:0]]<=config_data[51:50];tail[config_data[VOICE_BITS-1:0]]<=config_data[53:52];
    if(config_data[51:50]==3)mod_freq[config_data[VOICE_BITS-1:0]]<=config_data[39:8]*3+(config_data[39:8]>>1);
    else mod_freq[config_data[VOICE_BITS-1:0]]<=config_data[39:8]<<1;
    attack[config_data[VOICE_BITS-1:0]]<=config_data[79:64];decay[config_data[VOICE_BITS-1:0]]<=config_data[95:80];
    sustain[config_data[VOICE_BITS-1:0]]<=config_data[111:96];release_step[config_data[VOICE_BITS-1:0]]<=config_data[127:112];
   end
  end
 end
endmodule

// Fractional clock enable; all logic remains in the 50 MHz domain.
// Average sample rate 48 kHz, BCLK half-period quantized to 20 ns.
module i2s_output #(parameter CLK_HZ=50000000)(
 input clk,input rst_n,input [15:0] pcm,output reg bck,output reg ws,output reg dout,output reg sample_tick);
 reg [31:0] fraction;reg [4:0] bitpos;reg [15:0] held;
 always @(posedge clk)begin
  if(!rst_n)begin fraction<=0;bck<=1;ws<=1;dout<=0;bitpos<=31;held<=0;sample_tick<=0;end
  else begin
   sample_tick<=0;
   if(fraction>=CLK_HZ-3072000)begin
    fraction<=fraction+3072000-CLK_HZ;bck<=!bck;
    if(bck)begin
     bitpos<=bitpos+1;
     dout<=held[15-bitpos[3:0]];
     if(bitpos==15)ws<=1;
     if(bitpos==31)begin ws<=0;held<=pcm;sample_tick<=1;end
    end
   end else fraction<=fraction+3072000;
  end
 end
endmodule
