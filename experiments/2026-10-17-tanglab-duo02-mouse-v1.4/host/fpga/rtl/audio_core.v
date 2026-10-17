module audio_core(input clk,input rst_n,input sample_tick,input config_valid,input [135:0] config_data,
 output reg [79:0] samples,output reg sample_valid,output reg [31:0] clips,
 input piano_config_valid,input [31:0] piano_config_data);
 reg [31:0] phase[0:3],freq[0:3];
 reg [15:0] gain[0:3];reg [2:0] wave[0:3];reg gate[0:3],old_gate[0:3];
 // Configurable body (default T10 = 6 s), hammer brightness (~85 ms).
 reg [23:0] piano_body[0:3],piano_bright[0:3];
 reg piano_hold[0:3];reg [15:0] piano_coefficient[0:3];reg [2:0] old_wave[0:3];
 reg [39:0] body_product;
 reg [3:0] state;reg [1:0] voice;
 reg [23:0] piano_fraction[0:3];
 wire [24:0] body_fraction_sum={1'b0,body_product[23:0]}+{1'b0,piano_fraction[voice]};
 wire [16:0] body_drop={1'b0,body_product[39:24]}+{16'b0,body_fraction_sum[24]};
 reg [15:0] env[0:3],attack[0:3],decay[0:3],sustain[0:3],release_step[0:3];
 reg [1:0] stage[0:3];integer i;
 wire signed [15:0] sine;
 reg [7:0] lut_addr;
 always @*begin
  case(state)
   6:lut_addr=phase[voice][31:24]*8'd2;
   7:lut_addr=phase[voice][31:24]*8'd3;
   8:lut_addr=phase[voice][31:24]*8'd4;
   default:lut_addr=phase[voice][31:24];
  endcase
 end
 sine_lut lut(.addr(lut_addr),.value(sine));
 reg signed [15:0] piano_fund,piano_partial,piano_tone;
 reg signed [32:0] piano_product;
 reg signed [15:0] osc;reg signed [32:0] prod1;reg signed [49:0] prod2;
 reg signed [17:0] sum;reg signed [15:0] voice_value;
 // Piano tails round to nearest PCM, ties away from zero. Arithmetic
 // truncation otherwise leaves a negative -1/0 tail after positive samples vanish.
 wire piano_round_up=prod2[31] && (!prod2[49] || |prod2[30:0]);
 wire [15:0] piano_rounded=prod2[47:32]+{15'b0,piano_round_up};
 always @*begin
  case(wave[voice])
   0:osc=sine;
   1:osc={~phase[voice][31],phase[voice][30:16]};
   2:osc=phase[voice][31]?-16'sd32767:16'sd32767;
   3:osc=phase[voice][31]?16'sd32767-$signed({1'b0,phase[voice][30:16]})*2:-16'sd32767+$signed({1'b0,phase[voice][30:16]})*2;
   default:osc=0;
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;voice<=0;sum<=0;samples<=0;sample_valid<=0;clips<=0;prod1<=0;prod2<=0;voice_value<=0;
   piano_fund<=0;piano_partial<=0;piano_tone<=0;piano_product<=0;body_product<=0;
   for(i=0;i<4;i=i+1)begin phase[i]<=0;freq[i]<=32'd33554432*(i+1);gain[i]<=46;wave[i]<=0;old_wave[i]<=0;gate[i]<=0;old_gate[i]<=0;env[i]<=0;attack[i]<=137;decay[i]<=17;sustain[i]<=45874;release_step[i]<=8;stage[i]<=0;piano_body[i]<=0;piano_bright[i]<=0;piano_hold[i]<=0;piano_coefficient[i]<=134;piano_fraction[i]<=0;end
  end else begin
   sample_valid<=0;
   if(piano_config_valid)begin
    piano_hold[piano_config_data[1:0]]<=piano_config_data[8];
    piano_coefficient[piano_config_data[1:0]]<=piano_config_data[31:16];
   end
   if(config_valid && config_data[7:0]<4)begin
    freq[config_data[1:0]]<=config_data[39:8];gain[config_data[1:0]]<={config_data[135:128],config_data[47:40]};wave[config_data[1:0]]<=config_data[50:48];gate[config_data[1:0]]<=config_data[56];
    attack[config_data[1:0]]<=config_data[79:64];decay[config_data[1:0]]<=config_data[95:80];sustain[config_data[1:0]]<=config_data[111:96];release_step[config_data[1:0]]<=config_data[127:112];
   end
   case(state)
    0:if(sample_tick)begin
     voice<=0;sum<=0;state<=1;
     for(i=0;i<4;i=i+1)begin
      phase[i]<=phase[i]+freq[i];old_gate[i]<=gate[i];old_wave[i]<=wave[i];
      if(piano_bright[i]!=0)piano_bright[i]<=piano_bright[i]-(piano_bright[i]>>12)-1'b1;
      if(gate[i] && (!old_gate[i] || (wave[i]==4 && old_wave[i]!=4)))begin
       stage[i]<=0;env[i]<=0;piano_body[i]<=24'hffffff;piano_bright[i]<=24'hffffff;piano_fraction[i]<=0;
       if(wave[i]==4)phase[i]<=0;
      end
      else if(!gate[i])begin if(env[i]<=release_step[i])env[i]<=0;else env[i]<=env[i]-release_step[i];end
      else case(stage[i])
       0:if({1'b0,env[i]}+{1'b0,attack[i]}>=65535)begin env[i]<=65535;stage[i]<=1;end else env[i]<=env[i]+attack[i];
       1:if(env[i]<={1'b0,sustain[i]}+{1'b0,decay[i]})begin env[i]<=sustain[i];stage[i]<=2;end else env[i]<=env[i]-decay[i];
       default:env[i]<=sustain[i];
      endcase
     end
    end
    1:begin
     if(wave[voice]==4)begin piano_fund<=sine>>>1;piano_partial<=0;state<=13;end
     else begin prod1<=osc*$signed({1'b0,env[voice]});state<=2;end
    end
    // Time-multiplex one sine ROM; omit partials at/above Nyquist.
    6:begin if(freq[voice]<32'h40000000)piano_partial<=piano_partial+(sine>>>2);state<=7;end
    7:begin if(freq[voice]<32'h2aaaaaab)piano_partial<=piano_partial+(sine>>>3);state<=8;end
    8:begin if(freq[voice]<32'h20000000)piano_partial<=piano_partial+(sine>>>4);state<=9;end
    9:begin piano_product<=piano_partial*$signed({1'b0,piano_bright[voice][23:8]});state<=10;end
    10:begin piano_tone<=piano_fund+$signed(piano_product[31:16]);state<=11;end
    11:begin piano_product<=piano_tone*$signed({1'b0,piano_body[voice][23:8]});state<=12;end
    12:begin prod1<=$signed(piano_product[31:16])*$signed({1'b0,env[voice]});state<=2;end
    // Unsigned Q0.24 coefficient, serialized multiply to preserve timing.
    13:begin body_product<=piano_body[voice]*piano_coefficient[voice];state<=14;end
    14:begin
     if(piano_hold[voice] && gate[voice])begin piano_body[voice]<=24'hffffff;piano_fraction[voice]<=0;end
     else begin
      // Accumulate the fractional loss: long T10 must not drift due to truncation.
      piano_fraction[voice]<=body_fraction_sum[23:0];
      piano_body[voice]<=piano_body[voice]-body_drop;
     end
     state<=6;
    end
    2:begin prod2<=prod1*$signed({1'b0,gain[voice]});state<=3;end
    3:begin voice_value<=wave[voice]==4?piano_rounded:(prod2>>>32);state<=4;end
    4:begin
     samples[voice*16+:16]<=voice_value;sum<=sum+voice_value;
     if(voice==3)state<=5;else begin voice<=voice+1;state<=1;end
    end
    5:begin
     if(sum>32767)begin samples[79:64]<=32767;clips<=clips+1;end
     else if(sum< -32768)begin samples[79:64]<=16'h8000;clips<=clips+1;end
     else samples[79:64]<=sum[15:0];
     sample_valid<=1;state<=0;
    end
   endcase
  end
 end
endmodule

// Fractional clock enable; all logic remains in the 50 MHz domain.
// PT8211 LSBJ, NOT Philips I2S: WS changes AFTER the previous LSB rising edge.
// Average sample rate 48 kHz, BCLK half-period quantized to 20 ns.
module i2s_output #(parameter CLK_HZ=50000000)(
 input clk,input rst_n,input [15:0] pcm,output reg bck,output reg ws,output reg dout,output reg sample_tick);
 reg [31:0] fraction;reg [4:0] bitpos;reg [15:0] held;
 always @(posedge clk)begin
  if(!rst_n)begin fraction<=0;bck<=1;ws<=1;dout<=0;bitpos<=0;held<=0;sample_tick<=0;end
  else begin
   sample_tick<=0;
   if(fraction>=CLK_HZ-3072000)begin
    fraction<=fraction+3072000-CLK_HZ;bck<=!bck;
    if(bck)begin
     bitpos<=bitpos+1;
     dout<=held[15-bitpos[3:0]];
     if(bitpos==16)ws<=1;
     if(bitpos==0)begin ws<=0;held<=pcm;dout<=pcm[15];sample_tick<=1;end
    end
   end else fraction<=fraction+3072000;
  end
 end
endmodule
