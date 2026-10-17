// Passive observation only: never backpressures or modifies the audio path.
// 1024 real samples/channel, symmetric Hann, forward FFT normalized by 1024.
// Serial radix-2 butterfly, one shared 24x16 complex multiplier.
// Output is transactional: wave/bin pulses belong to frame_id; commit on done.
// Consumers must discard partial transactions across rst_n and only show done.
module stereo_fft_observer(
 input clk,rst_n,input pcm_valid,input signed[15:0]pcm_left,pcm_right,
 output busy,output reg frame_start,frame_done,output reg[31:0]frame_id,
 output reg bin_valid,bin_channel,output reg[9:0]bin_index,
 output reg signed[23:0]bin_real,bin_imag,
 output reg wave_valid,wave_channel,output reg[5:0]wave_column,
 output reg signed[15:0]wave_min,wave_max,
 output reg[31:0]dropped_blocks,completed_frames,output reg[31:0]last_cycles,max_cycles
);
 reg[31:0]capture[0:2047] /* synthesis syn_ramstyle="block_ram" */;
 reg[47:0]scratch[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 reg[31:0]twiddles[0:511] /* synthesis syn_romstyle="block_rom" */;
 reg[15:0]hann[0:1023] /* synthesis syn_romstyle="block_rom" */;
 initial begin
  $readmemh("rtl/fft_twiddle.hex",twiddles);
  $readmemh("rtl/fft_hann.hex",hann);
 end
 reg[4:0]state;
 assign busy=state!=0;
 reg[9:0]capture_index,load_index,out_index;
 reg capture_bank,capture_allowed,work_bank,channel;
 reg[31:0]block_id,cycle_count;
 reg[31:0]cap_q,twiddle_q;
 reg[15:0]hann_q;
 reg[47:0]ram_q;
 reg signed[15:0]wr,wi,lo,hi;
 reg signed[23:0]ar,ai,br,bi;
 reg signed[31:0]window_product;
 reg signed[39:0]product,rr,ii,ri,ir;
 reg signed[25:0]tr,ti;
 reg[3:0]stage;
 reg[9:0]group_base,j,half_size,tw_index,tw_step;
 reg[10:0]span;
 wire[9:0]a_address=group_base+j;
 wire[9:0]b_address=a_address+half_size;
 wire[10:0]next_group={1'b0,group_base}+span;
 wire signed[15:0]raw_sample=channel ? $signed(cap_q[31:16]) : $signed(cap_q[15:0]);
 function[9:0]reverse10(input[9:0]v);
  integer k;begin for(k=0;k<10;k=k+1)reverse10[k]=v[9-k];end
 endfunction
 wire signed[40:0]real_product=$signed({rr[39],rr})-$signed({ii[39],ii});
 wire signed[40:0]imag_product=$signed({ri[39],ri})+$signed({ir[39],ir});
 wire signed[26:0]a_real_ext={{3{ar[23]}},ar},a_imag_ext={{3{ai[23]}},ai};
 wire signed[26:0]t_real_ext={tr[25],tr},t_imag_ext={ti[25],ti};
 wire signed[26:0]plus_real=(a_real_ext+t_real_ext)>>>1;
 wire signed[26:0]plus_imag=(a_imag_ext+t_imag_ext)>>>1;
 wire signed[26:0]minus_real=(a_real_ext-t_real_ext)>>>1;
 wire signed[26:0]minus_imag=(a_imag_ext-t_imag_ext)>>>1;
 wire signed[31:0]window_scaled=window_product>>>7; // PCM * Q15 -> PCM * 256
 wire signed[23:0]multiply_b=(state==8 || state==10) ? bi : br;
 wire signed[15:0]multiply_w=(state==8 || state==9) ? wi : wr;
 reg[9:0]write_address;reg[47:0]write_data;
 wire write_enable=state==3 || state==13 || state==14;
 always @*begin
  write_address=a_address;write_data={plus_real[23:0],plus_imag[23:0]};
  if(state==3)begin write_address=reverse10(load_index);write_data={window_scaled[23:0],24'd0};end
  else if(state==14)begin write_address=b_address;write_data={minus_real[23:0],minus_imag[23:0]};end
 end
 reg[9:0]ram_address;
 always @*begin
  ram_address=a_address;
  if(state==5)ram_address=b_address;
  else if(state==15)ram_address=out_index;
 end
 // Synchronous memory access; do not reset a RAM with a clearing loop.
 always @(posedge clk)begin
  if(rst_n && pcm_valid && (capture_allowed || (capture_index==0 && !busy)))
   capture[{capture_bank,capture_index}]<={pcm_right,pcm_left};
  if(state==1)begin
   cap_q<=capture[{work_bank,load_index}];hann_q<=hann[load_index];
  end
  if(state==4)twiddle_q<=twiddles[tw_index];
  if(state==4 || state==5 || state==15)ram_q<=scratch[ram_address];
  if(rst_n && write_enable)scratch[write_address]<=write_data;
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;capture_index<=0;capture_bank<=0;capture_allowed<=1;work_bank<=0;
   channel<=0;load_index<=0;out_index<=0;block_id<=0;cycle_count<=0;
   frame_start<=0;frame_done<=0;frame_id<=0;completed_frames<=0;dropped_blocks<=0;
   bin_valid<=0;bin_channel<=0;bin_index<=0;bin_real<=0;bin_imag<=0;
   wave_valid<=0;wave_channel<=0;wave_column<=0;wave_min<=0;wave_max<=0;
   last_cycles<=0;max_cycles<=0;ar<=0;ai<=0;br<=0;bi<=0;wr<=0;wi<=0;
   lo<=0;hi<=0;window_product<=0;product<=0;rr<=0;ii<=0;ri<=0;ir<=0;tr<=0;ti<=0;
   stage<=0;group_base<=0;j<=0;half_size<=1;span<=2;tw_index<=0;tw_step<=512;
  end else begin
   frame_start<=0;frame_done<=0;bin_valid<=0;wave_valid<=0;
   if(busy)cycle_count<=cycle_count+1'b1;
   if(pcm_valid)begin
    // A bank skipped under overload becomes available at the next block start.
    // Re-arm before its first word, never half way through a block.
    if(capture_index==0 && !busy)capture_allowed<=1;
    capture_index<=capture_index+1'b1;
    if(capture_index==1023)begin
     capture_bank<=!capture_bank;block_id<=block_id+1'b1;
     // Reserve work_bank until both channels are copied and transformed.
     // When overloaded skip a whole monitor block, never stall the DAC.
     capture_allowed<=!busy || ((!capture_bank)!=work_bank);
     if(capture_allowed && !busy)begin
      work_bank<=capture_bank;frame_id<=block_id;frame_start<=1;
      state<=1;load_index<=0;channel<=0;cycle_count<=0;
     end else if(dropped_blocks!=32'hffffffff)dropped_blocks<=dropped_blocks+1'b1;
    end
   end
   case(state)
    0:begin end
    1:state<=2;
    2:begin
     window_product<=raw_sample*$signed(hann_q);
     if(load_index[3:0]==0)begin lo<=raw_sample;hi<=raw_sample;end
     else begin if(raw_sample<lo)lo<=raw_sample;if(raw_sample>hi)hi<=raw_sample;end
     state<=3;
    end
    3:begin
     if(load_index[3:0]==15)begin
      wave_valid<=1;wave_channel<=channel;wave_column<=load_index[9:4];wave_min<=lo;wave_max<=hi;
     end
     if(load_index==1023)begin
      stage<=0;group_base<=0;j<=0;half_size<=1;span<=2;tw_index<=0;tw_step<=512;state<=4;
     end else begin load_index<=load_index+1'b1;state<=1;end
    end
    4:state<=5;
    5:begin ar<=$signed(ram_q[47:24]);ai<=$signed(ram_q[23:0]);state<=6;end
    6:begin
     br<=$signed(ram_q[47:24]);bi<=$signed(ram_q[23:0]);
     wr<=$signed(twiddle_q[31:16]);wi<=$signed(twiddle_q[15:0]);state<=7;
    end
    // Four operations through the same physical multiply expression.
    7,8,9,10:begin
     product<=multiply_b*multiply_w;
     case(state)
      8:rr<=product;
      9:ii<=product;
      10:ri<=product;
     endcase
     state<=state+1'b1;
    end
    11:begin ir<=product;state<=12;end
    12:begin
     // Q1.15 cannot represent +1. Preserve the exact unity butterfly instead
     // of attenuating DC/Nyquist by 32767/32768 on every stage.
     tr<=tw_index==0 ? $signed(br) : real_product>>>15;
     ti<=tw_index==0 ? $signed(bi) : imag_product>>>15;state<=13;
    end
    13:state<=14;
    14:begin
     if(j+1'b1==half_size)begin
      j<=0;tw_index<=0;
      if(next_group==1024)begin
       group_base<=0;
       if(stage==9)begin out_index<=0;state<=15;end
       else begin stage<=stage+1'b1;half_size<=half_size<<1;span<=span<<1;tw_step<=tw_step>>1;state<=4;end
      end else begin group_base<=next_group[9:0];state<=4;end
     end else begin j<=j+1'b1;tw_index<=tw_index+tw_step;state<=4;end
    end
    15:state<=16;
    16:begin
     bin_valid<=1;bin_channel<=channel;bin_index<=out_index;
     bin_real<=$signed(ram_q[47:24]);bin_imag<=$signed(ram_q[23:0]);
     if(out_index==512)begin
      if(!channel)begin channel<=1;load_index<=0;state<=1;end
      else begin
       frame_done<=1;completed_frames<=completed_frames+1'b1;last_cycles<=cycle_count+1'b1;
       if(cycle_count+1'b1>max_cycles)max_cycles<=cycle_count+1'b1;state<=0;
      end
     end else begin out_index<=out_index+1'b1;state<=15;end
    end
    default:state<=0;
   endcase
  end
 end
endmodule
