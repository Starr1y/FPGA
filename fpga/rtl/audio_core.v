module audio_core(input clk,input rst_n,input sample_tick,input config_valid,input [127:0] config_data,
 output reg [79:0] samples,output reg sample_valid,output reg [31:0] clips);
 reg [31:0] phase[0:3],freq[0:3];
 reg [7:0] gain[0:3];reg [1:0] wave[0:3];reg gate[0:3],old_gate[0:3];
 reg [15:0] env[0:3],attack[0:3],decay[0:3],sustain[0:3],release_step[0:3];
 reg [1:0] stage[0:3];integer i;
 reg [3:0] state;reg [1:0] voice;
 wire signed [15:0] sine;
 sine_lut lut(.addr(phase[voice][31:24]),.value(sine));
 reg signed [15:0] osc;reg signed [32:0] prod1;reg signed [41:0] prod2;
 reg signed [17:0] sum;reg signed [15:0] voice_value;
 always @*begin
  case(wave[voice])
   0:osc=sine;
   1:osc={~phase[voice][31],phase[voice][30:16]};
   2:osc=phase[voice][31]?-16'sd32767:16'sd32767;
   3:osc=phase[voice][31]?16'sd32767-$signed({1'b0,phase[voice][30:16]})*2:-16'sd32767+$signed({1'b0,phase[voice][30:16]})*2;
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;voice<=0;sum<=0;samples<=0;sample_valid<=0;clips<=0;prod1<=0;prod2<=0;voice_value<=0;
   for(i=0;i<4;i=i+1)begin phase[i]<=0;freq[i]<=32'd33554432*(i+1);gain[i]<=46;wave[i]<=0;gate[i]<=0;old_gate[i]<=0;env[i]<=0;attack[i]<=137;decay[i]<=17;sustain[i]<=45874;release_step[i]<=8;stage[i]<=0;end
  end else begin
   sample_valid<=0;
   if(config_valid && config_data[7:0]<4)begin
    freq[config_data[1:0]]<=config_data[39:8];gain[config_data[1:0]]<=config_data[47:40];wave[config_data[1:0]]<=config_data[49:48];gate[config_data[1:0]]<=config_data[56];
    attack[config_data[1:0]]<=config_data[79:64];decay[config_data[1:0]]<=config_data[95:80];sustain[config_data[1:0]]<=config_data[111:96];release_step[config_data[1:0]]<=config_data[127:112];
   end
   case(state)
    0:if(sample_tick)begin
     voice<=0;sum<=0;state<=1;
     for(i=0;i<4;i=i+1)begin
      phase[i]<=phase[i]+freq[i];old_gate[i]<=gate[i];
      if(gate[i] && !old_gate[i])begin stage[i]<=0;env[i]<=0;end
      else if(!gate[i])begin if(env[i]<=release_step[i])env[i]<=0;else env[i]<=env[i]-release_step[i];end
      else case(stage[i])
       0:if({1'b0,env[i]}+{1'b0,attack[i]}>=65535)begin env[i]<=65535;stage[i]<=1;end else env[i]<=env[i]+attack[i];
       1:if(env[i]<={1'b0,sustain[i]}+{1'b0,decay[i]})begin env[i]<=sustain[i];stage[i]<=2;end else env[i]<=env[i]-decay[i];
       default:env[i]<=sustain[i];
      endcase
     end
    end
    1:begin prod1<=osc*$signed({1'b0,env[voice]});state<=2;end
    2:begin prod2<=prod1*$signed({1'b0,gain[voice]});state<=3;end
    3:begin voice_value<=prod2>>>24;state<=4;end
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
