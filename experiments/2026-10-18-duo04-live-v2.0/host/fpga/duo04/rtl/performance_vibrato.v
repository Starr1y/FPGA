// Per-hand deliberate pitch vibrato. Q16 ratios; disabled is exactly unity.
// Rate phase increments are calculated by the host for a 48kHz sample enable.
module performance_vibrato(input clk,rst_n,sample_tick,input[63:0]rate_words,input[15:0]depth_cents,
 output reg[39:0]ratios);
 reg[31:0]phase0,phase1;wire signed[15:0]sine0,sine1;
 sine_lut left_lfo(.addr(phase0[31:22]),.value(sine0));
 sine_lut right_lfo(.addr(phase1[31:22]),.value(sine1));
 wire signed[24:0]amount0=sine0*$signed({1'b0,depth_cents[7:0]});
 wire signed[24:0]amount1=sine1*$signed({1'b0,depth_cents[15:8]});
 wire signed[9:0]cent0=amount0>>>15,cent1=amount1>>>15;
 wire[8:0]address0=cent0+10'sd230,address1=cent1+10'sd230;
 reg[19:0]cent_rom[0:511];initial $readmemh("rtl/cent_ratio.hex",cent_rom);
 always @(posedge clk)begin
  if(!rst_n)begin phase0<=0;phase1<=0;ratios<={20'd65536,20'd65536};end
  else begin
   if(sample_tick)begin phase0<=depth_cents[7:0]==0 ? 0 : phase0+rate_words[31:0];phase1<=depth_cents[15:8]==0 ? 0 : phase1+rate_words[63:32];end
   ratios[19:0]<=depth_cents[7:0]==0 ? 20'd65536 : cent_rom[address0];
   ratios[39:20]<=depth_cents[15:8]==0 ? 20'd65536 : cent_rom[address1];
  end
 end
endmodule
