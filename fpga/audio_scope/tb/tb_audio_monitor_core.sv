`timescale 1ns/1ps
module tb_audio_monitor_core;
 reg core_clk=0;always #10 core_clk=~core_clk;
 reg pixel_clk=0;initial begin #3.7;forever #20 pixel_clk=~pixel_clk;end
 reg core_reset_n=0,pixel_reset_n=0,pcm_valid=0;
 reg signed[15:0]pcm_left=0,pcm_right=0;
 reg[31:0]active=32'haaaa5555,owned=32'hf0f00f0f,gates=32'h3333cccc;
 reg[223:0]notes;reg[511:0]envelopes;
 wire observer_busy;wire[31:0]observer_drops,observer_frames,published_frames,skipped_frames,invalid_frames;
 reg frame_request=0,pixel_read_en=0;reg[8:0]pixel_address=0;
 wire[31:0]pixel_data,pixel_frame_id;wire pixel_frame_valid,pixel_updated;
 audio_monitor_core dut(.*);
 reg[31:0]vectors[0:9215];string data_file,result_file;integer fd,read_frames=0,samples=0;
 reg[18:0]raster=0;
 always @(posedge pixel_clk)begin
  if(!pixel_reset_n)begin raster<=0;frame_request<=0;end
  else begin
   raster<=raster==419999 ? 0 : raster+1'b1;
   frame_request<=raster==383998;
  end
 end
 initial begin
  if(!$value$plusargs("DATA=%s",data_file) || !$value$plusargs("RESULT=%s",result_file))$fatal(1,"provide DATA/RESULT");
  $readmemh(data_file,vectors);fd=$fopen(result_file,"w");if(!fd)$fatal(1,"output file");
  for(integer v=0;v<32;v=v+1)begin notes[v*7+:7]=48+v;envelopes[v*16+:16]=1000+v*500;end
  repeat(5)@(negedge pixel_clk);core_reset_n=1;pixel_reset_n=1;
  for(integer frame=0;frame<3;frame=frame+1)begin
   for(integer k=0;k<1024;k=k+1)begin
    @(negedge core_clk);{pcm_right,pcm_left}=vectors[(frame==0 ? 3 : frame==1 ? 5 : 7)*1024+k];pcm_valid=1;
    @(negedge core_clk);pcm_valid=0;
    repeat(samples%3==2 ? 1039 : 1040)@(negedge core_clk);samples++;
   end
  end
  wait(read_frames==3);repeat(5)@(negedge core_clk);
  if(observer_drops || skipped_frames || invalid_frames || observer_frames!=3 || published_frames!=3)$fatal(1,"real FFT snapshot frame rejected/dropped");
  $fclose(fd);$display("TB_PASS real stereo FFT through banked snapshot to 25MHz pixel reads: 3 complete frames, 32Voice metadata, no drops/invalids");$finish;
 end
 initial begin
  wait(pixel_reset_n);
  repeat(3)begin
   @(posedge pixel_updated);
   if(!pixel_frame_valid || pixel_frame_id!=read_frames)$fatal(1,"pixel frame order");
   for(integer address=0;address<512;address=address+1)begin
    @(negedge pixel_clk);pixel_read_en=1;pixel_address=address;
    @(posedge pixel_clk);#1;
    if(pixel_frame_id!=read_frames || ^pixel_data===1'bx)$fatal(1,"pixel frame tearing/unknown");
    $fdisplay(fd,"R %0d %0d %08x",read_frames,address,pixel_data);
   end
   @(negedge pixel_clk);pixel_read_en=0;read_frames++;
  end
 end
 initial begin #120000000;$fatal(1,"core watchdog");end
endmodule
