// Shared per-sample engine. No recorded PCM: modal/FM oscillators and a
// fractional, damped feedback string. One 1024-word ring per Voice, C2 minimum.
module four_timbres #(parameter VOICES=32, VB=$clog2(VOICES))(
 input clk,rst_n,start,trigger,hold_body,input[VB-1:0]voice,
 input[1:0]kind,input[6:0]note,input[31:0]phase,frequency,
 input[7:0]velocity,brightness,input[15:0]decay_coefficient,
 output reg done,output reg signed[15:0]value);
 reg[3:0]state;reg[VB-1:0]v;reg[1:0]k;reg hit,held;
 reg[31:0]p,f;reg[6:0]n;reg[7:0]vel,bright;reg[15:0]coefficient;
 reg[23:0]energy[0:VOICES-1],fraction[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg[9:0]seed_words[0:VOICES-1],pointer[0:VOICES-1],valid_words[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg[22:0]delay_rom[0:127];
 reg[22:0]reciprocal_rom[0:2047];reg[22:0]delay0,delay1;reg[38:0]delay_product;
 wire[10:0]frequency_index=frequency[31:16]>2046 ? 11'd2046 : frequency[26:16];
 wire[22:0]interpolated_delay=delay0-(delay_product>>16);reg[9:0]delay_int;reg[11:0]delay_frac;
 reg[14:0]read_address,write_address;reg signed[15:0]a,b,previous[0:VOICES-1] /* synthesis syn_ramstyle="registers" */;
 reg signed[15:0]string_memory[0:VOICES*1024-1] /* synthesis syn_ramstyle="block_ram" */;
 reg signed[15:0]ram_data;
 wire[14:0]ram_address=state==2 ? read_address : v*1024+((read_address-1)&1023);
 always @(posedge clk)if(state==2 || state==3)ram_data<=string_memory[ram_address];
 reg[31:0]noise=32'h13579bdf;reg[23:0]body;reg[39:0]loss;
 reg signed[15:0]sine0,sine1,sine2,sine3;reg signed[24:0]ep_modulation;
 reg[15:0]harmonic_velocity,harmonic_brightness;
 reg signed[31:0]partial_sum;reg signed[56:0]shaped;
 reg signed[29:0]interpolated;reg signed[17:0]filtered;
 reg[31:0]ep_phase;wire signed[15:0]s0,s1,s2,s3,modulator;
 wire[31:0]fund_phase=k==2 ? ep_phase : p;
 wire[31:0]p1=k==1 ? p<<2 : p<<1;
 wire[31:0]p2=k==1 ? (p<<3)+(p<<1) : p+(p<<1);
 wire[31:0]p3=p<<2;
 sine_lut fundamental(.addr(fund_phase[31:22]),.value(s0));
 sine_lut partial1(.addr(p1[31:22]),.value(s1));
 sine_lut partial2(.addr(p2[31:22]),.value(s2));
 sine_lut partial3(.addr(p3[31:22]),.value(s3));
 sine_lut fm_modulator(.addr(p1[31:22]),.value(modulator));
 integer i;
 initial begin $readmemh("rtl/string_delays.hex",delay_rom);$readmemh("rtl/string_reciprocal.hex",reciprocal_rom);end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;done<=0;value<=0;noise<=32'h13579bdf;
   for(i=0;i<VOICES;i=i+1)begin energy[i]<=0;fraction[i]<=0;pointer[i]<=0;valid_words[i]<=0;previous[i]<=0;end
  end else begin
   done<=0;
   noise<={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
   case(state)
    0:if(start)begin
     v<=voice;k<=kind;p<=phase;f<=frequency;n<=note;vel<=velocity;bright<=brightness;
     delay0<=reciprocal_rom[frequency_index];delay1<=reciprocal_rom[frequency_index+1'b1];
     coefficient<=note<48 ? (decay_coefficient>>1)+(decay_coefficient>>2) : note>=72 ? decay_coefficient+(decay_coefficient>>1) : decay_coefficient;hit<=trigger;held<=hold_body;
     body<=trigger ? 24'hffffff : energy[voice];
     if(trigger)begin pointer[voice]<=0;valid_words[voice]<=0;previous[voice]<=0;fraction[voice]<=0;end
     state<=1;
    end
    1:begin
     // Coefficients are Q24 rates; note tables tune bass/treble separately.
     delay_product<=(delay0-delay1)*f[15:0];
     loss<=body*(k==1 ? 16'd1400 : k==2 ? 16'd110 : coefficient);
     ep_modulation<=$signed(modulator)*$signed({1'b0,vel});
     harmonic_velocity<=vel*body[23:16];harmonic_brightness<=bright*body[23:16];
     state<=6;
    end
    6:begin
     ep_phase<=p+ep_modulation*$signed({1'b0,body[23:16]});
     delay_int<=interpolated_delay[21:12];delay_frac<=interpolated_delay[11:0];
     read_address<=v*1024+((pointer[v]-interpolated_delay[21:12]) & 10'h3ff);
     write_address<=v*1024+pointer[v];state<=8;
    end
    8:begin sine0<=s0;sine1<=s1;sine2<=s2;sine3<=s3;state<=2;end
    2:begin

     case(k)
      0:partial_sum<=($signed(sine0)*32'sd5>>>3)+
        (f<32'h40000000 ? ($signed(sine1)*$signed({1'b0,harmonic_velocity})>>>18) : 32'sd0)+
        (f<32'h2aaaaaaa ? ($signed(sine2)*$signed({1'b0,harmonic_velocity})>>>19) : 32'sd0)+
        (f<32'h20000000 ? ($signed(sine3)*$signed({1'b0,harmonic_brightness})>>>20) : 32'sd0);
      1:partial_sum<=($signed(sine0)*32'sd3>>>2)+(f<32'h20000000 ? ($signed(sine1)*32'sd3>>>4) : 32'sd0)+
        (f<32'h0ccccccc ? ($signed(sine2)>>>4) : 32'sd0);
      default:partial_sum<=($signed(sine0)*32'sd3>>>2);
     endcase
     state<=3;
    end
    3:begin
     a<=ram_data;
     shaped<=partial_sum*$signed({1'b0,body});

     if(hit || (held && k==0))begin energy[v]<=24'hffffff;fraction[v]<=0;end
     else if(body!=0)begin
      if(body<=((loss+fraction[v])>>24))begin energy[v]<=0;fraction[v]<=0;end
      else begin energy[v]<=body-((loss+fraction[v])>>24);fraction[v]<=loss[23:0]+fraction[v];end
     end
     state<=4;
    end
    4:begin
     interpolated<=$signed(a)*$signed(14'd4096-{2'b0,delay_frac})+$signed(ram_data)*$signed({1'b0,delay_frac});state<=7;
    end
    7:begin
     // Seed only the newly excited delay window, never reuse a previous note.
     if(hit)seed_words[v]<=delay_int+2;
     if(valid_words[v]<1023)valid_words[v]<=valid_words[v]+1'b1;
     if(valid_words[v]<(hit ? delay_int+2 : seed_words[v]))filtered<=$signed(noise[31:16])>>>2;
     else if(valid_words[v]<delay_int+2)filtered<=0;
     else filtered<=($signed(interpolated)>>>13)+($signed(previous[v])>>>1);
     state<=5;
    end
    5:begin
     if(k==3)begin
      string_memory[write_address]<=filtered-($signed(filtered)>>>10);
      previous[v]<=interpolated>>>12;pointer[v]<=pointer[v]+1'b1;
     end
     if(k==3)value<=valid_words[v]<=2 ? 0 : filtered[15:0];
     else if((shaped>>>24)>32767)value<=32767;
     else if((shaped>>>24)< -32768)value<=-32768;
     else value<=shaped>>>24;
     done<=1;state<=0;
    end
   endcase
  end
 end
endmodule
