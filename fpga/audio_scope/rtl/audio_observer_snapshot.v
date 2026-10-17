// Atomic audio observation store. Independent from the frozen board versions.
// Core writes only the bank not visible to the pixel reader. The published bank
// is held until the pixel domain adopts it in vertical blank and acknowledges.
// Both resets must be asserted together; independent reset recovery is not used.
module audio_observer_snapshot(
 input core_clk,core_reset_n,input frame_start,frame_done,input[31:0]frame_id,
 input bin_valid,bin_channel,input[9:0]bin_index,input signed[23:0]bin_real,bin_imag,
 input wave_valid,wave_channel,input[5:0]wave_column,input signed[15:0]wave_min,wave_max,
 input[31:0]active,owned,gates,input[223:0]notes,input[511:0]envelopes,
 input[31:0]observer_cycles,observer_drops,
 output reg[31:0]published_frames,skipped_frames,invalid_frames,
 input pixel_clk,pixel_reset_n,input frame_request,input pixel_read_en,input[8:0]pixel_address,
 output reg[31:0]pixel_data,output reg pixel_frame_valid,output reg[31:0]pixel_frame_id,
 output reg pixel_updated
);
 // 0..63/64..127: L/R raw 16-sample waveform min/max (16 bits each).
 // 128..191/192..255: L/R 64-band |real|+|imag| maxima, bits24:0.
 // 256..287: voices {reserved6, envelope16, MIDI7, active, gate, owned}.
 // 288: block id, 289: observer clocks, 290: observer drops, 291: skipped frames.
 // Pixel address >=292 is outside the initialized frame and returns zero.
 reg[31:0]memory[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 reg[2:0]state; // 0 idle, 1 collect, 2/3 drain, 4 voices, 5 metadata
 reg work_bank,published_bank,publish_toggle,transaction_bad;
 reg[1:0]ack_sync;reg[2:0]publish_sync;
 reg pixel_ack,pixel_bank;
 reg[31:0]held_id,published_id,held_cycles,held_drops;
 reg[831:0]held_voices;
 reg[4:0]voice_index;reg[1:0]meta_index;
 reg[7:0]wave_count,bar_count;
 reg[10:0]bin_count;
 reg[6:0]expected_wave;reg expected_channel;reg[9:0]expected_bin;
 reg bin_pending,channel_q;reg[9:0]index_q;reg[5:0]band_q,current_band;
 reg[24:0]magnitude_q,current_peak;
 reg bar_valid,bar_channel;reg[5:0]bar_index;reg[24:0]bar_magnitude;
 function[23:0]absolute24(input signed[23:0]v);begin absolute24=v[23] ? -v : v;end endfunction
 // First 32 bands are individual bins. Remaining bands subdivide each octave
 // into eight equal-bin groups (not exact logarithmic or semitone spacing).
 function[5:0]band_for(input[9:0]k);
  reg[3:0]lead;reg[9:0]fraction;reg[6:0]value;
  begin
   if(k<=32)band_for=k==0 ? 0 : k-1'b1;
   else begin
    lead=k>=512 ? 9 : k>=256 ? 8 : k>=128 ? 7 : k>=64 ? 6 : 5;
    fraction=k>>(lead-3);value=32+((lead-5)<<3)+(fraction & 7);
    band_for=value>63 ? 63 : value[5:0];
   end
  end
 endfunction
 wire[24:0]magnitude={1'b0,absolute24(bin_real)}+{1'b0,absolute24(bin_imag)};
 wire[24:0]peak_with_current=magnitude_q>current_peak ? magnitude_q : current_peak;
 reg write_en;reg[8:0]write_address;reg[31:0]write_data;
 always @*begin
  write_en=0;write_address=0;write_data=0;
  if(state==1 || state==2 || state==3)begin
   if(wave_valid && state==1)begin
    write_en=1;write_address={2'b0,wave_channel,wave_column};write_data={wave_max,wave_min};
   end else if(bar_valid)begin
    write_en=1;write_address=9'd128+{2'b0,bar_channel,bar_index};write_data={7'b0,bar_magnitude};
   end
  end else if(state==4)begin
   write_en=1;write_address=9'd256+voice_index;
   write_data={6'b0,held_voices[voice_index*26+:26]};
  end else if(state==5)begin
   write_en=1;write_address=9'd288+meta_index;
   case(meta_index)
    0:write_data=held_id;
    1:write_data=held_cycles;
    2:write_data=held_drops;
    3:write_data=skipped_frames;
   endcase
  end
 end
 // Single write port in core domain, synchronous read in pixel domain.
 always @(posedge core_clk)if(core_reset_n && write_en)memory[{work_bank,write_address}]<=write_data;
 always @(posedge pixel_clk)begin
  if(pixel_read_en)pixel_data<=pixel_frame_valid && pixel_address<292 ? memory[{pixel_bank,pixel_address}] : 32'd0;
 end
 integer v;
 always @(posedge core_clk)begin
  if(!core_reset_n)begin
   state<=0;work_bank<=1;published_bank<=0;publish_toggle<=0;ack_sync<=0;
   transaction_bad<=0;held_id<=0;published_id<=0;held_cycles<=0;held_drops<=0;held_voices<=0;
   voice_index<=0;meta_index<=0;published_frames<=0;skipped_frames<=0;invalid_frames<=0;
   wave_count<=0;bar_count<=0;bin_count<=0;expected_wave<=0;expected_channel<=0;expected_bin<=0;
   bin_pending<=0;channel_q<=0;index_q<=0;band_q<=0;magnitude_q<=0;current_band<=0;current_peak<=0;
   bar_valid<=0;bar_channel<=0;bar_index<=0;bar_magnitude<=0;
  end else begin
   ack_sync<={ack_sync[0],pixel_ack};bin_pending<=0;bar_valid<=0;
   if(frame_start)begin
    if(state==0 && publish_toggle==ack_sync[1])begin
     work_bank<=!published_bank;held_id<=frame_id;transaction_bad<=0;
     wave_count<=0;bar_count<=0;bin_count<=0;expected_wave<=0;expected_channel<=0;expected_bin<=0;
     current_band<=0;current_peak<=0;state<=1;
     for(v=0;v<32;v=v+1)held_voices[v*26+:26]<={envelopes[v*16+:16],notes[v*7+:7],active[v],gates[v],owned[v]};
    end else if(skipped_frames!=32'hffffffff)skipped_frames<=skipped_frames+1'b1;
   end
   if(state==1)begin
    if(wave_valid)begin
     if({wave_channel,wave_column}!=expected_wave || wave_count>=128)transaction_bad<=1;
     expected_wave<=expected_wave+1'b1;wave_count<=wave_count+1'b1;
    end
    if(bin_valid)begin
     if(bin_channel!=expected_channel || bin_index!=expected_bin || bin_count>=1026)transaction_bad<=1;
     bin_count<=bin_count+1'b1;
     if(bin_index==512)begin expected_channel<=1;expected_bin<=0;end else expected_bin<=expected_bin+1'b1;
     bin_pending<=1;channel_q<=bin_channel;index_q<=bin_index;band_q<=band_for(bin_index);magnitude_q<=magnitude;
    end
    if(frame_done)begin state<=2;held_cycles<=observer_cycles;held_drops<=observer_drops;end
   end
   // Drain the final Nyquist bin before validating and serializing metadata.
   if(bin_pending && (state==1 || state==2))begin
    if(index_q==0)begin current_band<=0;current_peak<=0;end
    else if(index_q==512)begin
     bar_valid<=1;bar_channel<=channel_q;bar_index<=63;bar_magnitude<=peak_with_current;
     current_peak<=0;
    end else if(band_q!=current_band)begin
     bar_valid<=1;bar_channel<=channel_q;bar_index<=current_band;bar_magnitude<=current_peak;
     current_band<=band_q;current_peak<=magnitude_q;
    end else current_peak<=peak_with_current;
   end
   if(bar_valid && (state==1 || state==2 || state==3))begin
    bar_count<=bar_count+1'b1;
    if(wave_valid && state==1)transaction_bad<=1; // Never publish an arbitrated-away write.
   end
   case(state)
    2:state<=3;
    3:if(!bar_valid && !bin_pending)begin
     if(transaction_bad || wave_count!=128 || bin_count!=1026 || bar_count!=128)begin
      state<=0;if(invalid_frames!=32'hffffffff)invalid_frames<=invalid_frames+1'b1;
     end else begin voice_index<=0;state<=4;end
    end
    4:if(voice_index==31)begin meta_index<=0;state<=5;end else voice_index<=voice_index+1'b1;
    5:if(meta_index==3)begin
     published_bank<=work_bank;published_id<=held_id;publish_toggle<=!publish_toggle;
     published_frames<=published_frames+1'b1;state<=0;
    end else meta_index<=meta_index+1'b1;
   endcase
  end
 end
 always @(posedge pixel_clk)begin
  if(!pixel_reset_n)begin publish_sync<=0;pixel_ack<=0;pixel_bank<=0;pixel_frame_valid<=0;pixel_frame_id<=0;pixel_updated<=0;end
  else begin
   publish_sync<={publish_sync[1:0],publish_toggle};pixel_updated<=0;
   if(frame_request && publish_sync[2]!=pixel_ack)begin
    pixel_ack<=publish_sync[2];pixel_bank<=published_bank;pixel_frame_id<=published_id;
    pixel_frame_valid<=1;pixel_updated<=1;
   end
  end
 end
endmodule
