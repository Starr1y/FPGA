// Tang Mega ordinary Dock: PT8211-S, 16-bit Japanese/LSBJ serial audio.
// WS=0 selects right, WS=1 selects left. DIN is sampled on rising BCK.
// Launch WS together with the new word's MSB, AFTER the previous LSB
// was sampled. There is no Philips-I2S one-bit delay at the WS boundary.
// Both input channels are captured atomically at the right-word start.
// All registers use clk; the fractional enable gives average 48 kHz.
module pt8211_output #(parameter CLK_HZ=50000000)(
 input clk,input rst_n,input [15:0] pcm_left,input [15:0] pcm_right,
 output reg bck,output reg ws,output reg dout,output reg sample_tick);
 reg [31:0] fraction;
 reg [4:0] slot;
 reg [15:0] held_left,held_right;
 always @(posedge clk)begin
  if(!rst_n)begin
   fraction<=0;slot<=0;held_left<=0;held_right<=0;
   bck<=1;ws<=0;dout<=0;sample_tick<=0;
  end else begin
   sample_tick<=0;
   if(fraction>=CLK_HZ-3072000)begin
    fraction<=fraction+3072000-CLK_HZ;bck<=!bck;
    if(bck)begin
     slot<=slot+1'b1;
     ws<=slot[4];
     if(slot==0)begin
      held_left<=pcm_left;held_right<=pcm_right;
      dout<=pcm_right[15];sample_tick<=1;
     end else if(!slot[4])dout<=held_right[15-slot[3:0]];
     else dout<=held_left[15-slot[3:0]];
    end
   end else fraction<=fraction+3072000;
  end
 end
endmodule
