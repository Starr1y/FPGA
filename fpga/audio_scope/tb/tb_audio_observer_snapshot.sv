`timescale 1ns/1ps
module tb_audio_observer_snapshot;
 reg core_clk=0;always #10 core_clk=~core_clk;
 reg pixel_clk=0;initial begin #3.7;forever #20 pixel_clk=~pixel_clk;end
 reg core_reset_n=0,pixel_reset_n=0;
 reg frame_start=0,frame_done=0,bin_valid=0,bin_channel=0,wave_valid=0,wave_channel=0;
 reg[31:0]frame_id=0,active=0,owned=0,gates=0,observer_cycles=0,observer_drops=0;
 reg[223:0]notes=0;reg[511:0]envelopes=0;
 reg[9:0]bin_index=0;reg signed[23:0]bin_real=0,bin_imag=0;
 reg[5:0]wave_column=0;reg signed[15:0]wave_min=0,wave_max=0;
 wire[31:0]published_frames,skipped_frames,invalid_frames;
 reg frame_request=0,pixel_read_en=0;reg[8:0]pixel_address=0;
 wire[31:0]pixel_data,pixel_frame_id;wire pixel_frame_valid,pixel_updated;
 audio_observer_snapshot dut(.*);
 integer fd,read_count=0;string output_file;
 task reset_all;
  begin
   @(negedge core_clk);core_reset_n=0;pixel_reset_n=0;frame_start=0;frame_done=0;bin_valid=0;wave_valid=0;frame_request=0;pixel_read_en=0;
   repeat(5)@(negedge pixel_clk);core_reset_n=1;pixel_reset_n=1;
   repeat(5)@(negedge core_clk);
  end
 endtask
 task begin_frame(input integer id);
  begin
   @(negedge core_clk);frame_id=id;observer_cycles=120836+id;observer_drops=id;
   for(integer v=0;v<32;v=v+1)begin
    active[v]=(v+id)%2;owned[v]=(v+id)%3!=0;gates[v]=(v+id)%4==0;
    notes[v*7+:7]=(id+v+48)%128;envelopes[v*16+:16]=id*100+v*17;
   end
   frame_start=1;@(negedge core_clk);frame_start=0;
   // Deliberately change live metadata after the capture edge.
   active=0;owned=0;gates=0;notes=0;envelopes=0;
  end
 endtask
 task send_frame(input integer id,input bit malformed);
  begin
   begin_frame(id);
   for(integer ch=0;ch<2;ch=ch+1)begin
    for(integer col=0;col<64;col=col+1)if(!(malformed && ch==0 && col==17))begin
     @(negedge core_clk);wave_valid=1;wave_channel=ch;wave_column=col;
     wave_min=-1000-id*10-col-ch*100;wave_max=2000+id*10+col+ch*100;
     @(negedge core_clk);wave_valid=0;
    end
    for(integer bin=0;bin<513;bin=bin+1)begin
     @(negedge core_clk);bin_valid=1;bin_channel=ch;bin_index=bin;
     bin_real=(id+1)*100+bin*3+ch*11;bin_imag=-bin-20;
     if(bin==257)begin bin_real=-24'sd8388608;bin_imag=-24'sd8388608;end
     if(ch==1 && bin==512)frame_done=1;
     @(negedge core_clk);bin_valid=0;frame_done=0;
    end
    // The FFT producer copies a new channel before its first waveform column.
    // Leave the final band pipeline time to drain before the next wave stream.
    repeat(4)@(negedge core_clk);
   end
   repeat(60)@(negedge core_clk);
  end
 endtask
 task adopt(input integer id);
  begin
   repeat(8)@(negedge pixel_clk);frame_request=1;
   @(negedge pixel_clk);frame_request=0;
   if(!pixel_frame_valid || pixel_frame_id!=id)$fatal(1,"frame not adopted in blank id %0d got %0d",id,pixel_frame_id);
   repeat(4)@(negedge core_clk);
  end
 endtask
 task read_all(input integer expected_id);
  begin
   for(integer address=0;address<512;address=address+1)begin
    @(negedge pixel_clk);pixel_read_en=1;pixel_address=address;
    @(posedge pixel_clk);#1;
    if(expected_id!=0 && pixel_frame_id!=expected_id)$fatal(1,"pixel bank changed outside request");
    if(^pixel_data===1'bx)$fatal(1,"uninitialized word exposed %0d",address);
    $fdisplay(fd,"R %0d %0d %08x",expected_id,address,pixel_data);read_count++;
   end
   @(negedge pixel_clk);pixel_read_en=0;
  end
 endtask
 always @(posedge pixel_clk)begin #1;if(pixel_updated && !frame_request)$fatal(1,"swap outside frame blank");end
 initial begin
  if(!$value$plusargs("RESULT=%s",output_file))$fatal(1,"provide RESULT");
  fd=$fopen(output_file,"w");if(!fd)$fatal(1,"result file");
  reset_all();read_all(0);
  send_frame(1,0);if(published_frames!=1 || pixel_frame_valid)$fatal(1,"presentation pub%0d invalid%0d state%0d bad%0d waves%0d bins%0d bars%0d",published_frames,invalid_frames,dut.state,dut.transaction_bad,dut.wave_count,dut.bin_count,dut.bar_count);
  send_frame(90,0);if(published_frames!=1 || skipped_frames!=1)$fatal(1,"no free presentation bank");
  adopt(1);
  fork read_all(1);send_frame(2,0);join
  if(published_frames!=2 || invalid_frames!=0)$fatal(1,"valid frame rejected");
  read_all(1);send_frame(91,0);if(skipped_frames!=2)$fatal(1,"pending frame overwritten");
  adopt(2);read_all(2);
  send_frame(4,1);
  if(invalid_frames!=1 || published_frames!=2)$fatal(1,"partial frame must not be published");
  adopt(2);read_all(2);
  begin_frame(5);repeat(5)@(negedge core_clk);reset_all();read_all(0);
  send_frame(9,0);adopt(9);read_all(9);
  if(published_frames!=1 || invalid_frames!=0 || skipped_frames!=0)$fatal(1,"reset counters");
  $fclose(fd);$display("TB_PASS atomic observer snapshot: two clocks, bank ownership/blank adoption, backpressure skip, malformed rejection, atomic32Voice metadata, reset, %0d word reads",read_count);$finish;
 end
 initial begin #5000000;$fatal(1,"snapshot watchdog");end
endmodule
