// One audio timebase, two simultaneous serial formats. PT8211 pins retain
// their original cycle-for-cycle LSBJ timing. External I2S uses 16-bit slots,
// MSB-first, WS=0 left/1 right, WS changes one bit before the next MSB.
// BCLK=32*48kHz. No MCLK: the external DAC must support this clock format.
module stereo_serial_output #(parameter CLK_HZ=50000000)(
 input clk,rst_n,input[15:0]pcm_left,pcm_right,
 output reg bck,ws,dout,output reg sample_tick,
 output i2s_bck,output reg i2s_ws,output reg i2s_dout);
 reg[31:0]fraction;reg[4:0]slot;reg[15:0]held_left,held_right;
 assign i2s_bck=bck;
 always @(posedge clk)begin
  if(!rst_n)begin fraction<=0;slot<=0;held_left<=0;held_right<=0;bck<=1;ws<=0;dout<=0;sample_tick<=0;i2s_ws<=0;i2s_dout<=0;end
  else begin
   sample_tick<=0;
   if(fraction>=CLK_HZ-3072000)begin
    fraction<=fraction+3072000-CLK_HZ;bck<=!bck;
    if(bck)begin
     slot<=slot+1'b1;ws<=slot[4];
     // PT starts right then left; I2S starts left then right. Both pairs
     // belong to the SAME slot0 capture. Do not only invert/delay PT WS:
     // that would join left[n] with right[n+1] in a standard I2S frame.
     i2s_ws<=slot>=15 && slot!=31;
     if(slot==0)i2s_dout<=pcm_left[15];
     else if(!slot[4])i2s_dout<=held_left[15-slot[3:0]];
     else i2s_dout<=held_right[15-slot[3:0]];
     if(slot==0)begin held_left<=pcm_left;held_right<=pcm_right;dout<=pcm_right[15];sample_tick<=1;end
     else if(!slot[4])dout<=held_right[15-slot[3:0]];
     else dout<=held_left[15-slot[3:0]];
    end
   end else fraction<=fraction+3072000;
  end
 end
endmodule
