`timescale 1ns/1ps
module tb_duo04_audio;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,sample_tick=0,config_valid=0;reg[127:0]config_data=0;
 wire config_ready,valid;wire[63:0]pcm;wire[3:0]release_due,active;
 reg[63:0]hold_samples={32'd240000,32'd4800};
 reg[27:0]all_notes={7'd60,7'd60,7'd60,7'd60};
 wire[15:0]max_cycles;wire[31:0]underflows;
 dual_audio_core #(.VOICES(4),.ENABLE_EXPRESSION(1)) dut(
 .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.config_valid(config_valid),.config_data(config_data),.config_ready(config_ready),
 .local_brightness(32'h80808080),.all_notes(all_notes),.hold_samples(hold_samples),.release_due(release_due),
 .glide_coefficients(48'b0),.vibrato_ratios({20'd65536,20'd65536}),.piano_hold(2'b00),.piano_coefficients({16'd134,16'd134}),
 .samples(),.sample_valid(valid),.clips(),.envelopes(),.all_envelopes(),.voice_samples(pcm),.active_voices(active),.underflows(underflows),
 .last_render_cycles(),.max_render_cycles(max_cycles),.monitor_voice(2'b0),.monitor_frequency(),.monitor_envelope(),.monitor_stage(),.stereo_left(),.stereo_right(),.stereo_clips());
 integer divider=0,frame=0,started[0:3],ended[0:3],i,note,kind,velocity,j,file;
 reg running=0;reg[31:0]ftw[0:127];
 always @(negedge clk)begin
  sample_tick=0;
  if(running)begin
   if(divider==199)begin divider=0;sample_tick=1;frame=frame+1;end else divider++;
  end
 end
 always @(posedge clk)if(rst_n)begin
  if(dut.state==13 && (dut.v_retrigger || (dut.v_gate && !dut.v_old_gate)))started[dut.voice]=frame;
  #1;
  for(integer v=0;v<4;v++)if(release_due[v])ended[v]=frame;
 end
 task cfg(input integer v,n,k,gain,gate);
 begin
  wait(config_ready);@(negedge clk);config_data=0;
  config_data[7:0]=v;config_data[39:8]=ftw[n];config_data[47:40]=gain;
  config_data[51:50]=k;config_data[55]=1;config_data[56]=gate;config_data[58]=gate;
  config_data[79:64]=1365;config_data[95:80]=137;config_data[111:96]=49152;config_data[127:112]=47;
  all_notes[v*7+:7]=n;config_valid=1;@(negedge clk);config_valid=0;
 end endtask
 initial begin
  $readmemh("rtl/midi_ftw.hex",ftw);file=$fopen("four_timbres.csv","w");$fwrite(file,"kind,note,velocity,index,value\n");
  for(i=0;i<4;i++)begin started[i]=-1;ended[i]=-1;end
  repeat(5)@(negedge clk);rst_n=1;running=1;
  cfg(0,60,0,96,1);cfg(2,60,2,96,1);
  hold_samples[31:0]=48000;cfg(1,60,1,96,1);
  hold_samples=64'd48; // Existing notes must retain their original durations.
  wait(ended[0]>=0 && ended[1]>=0 && ended[2]>=0);
  if(ended[0]-started[0]!=4800 || ended[1]-started[1]!=48000 || ended[2]-started[2]!=240000)
   $fatal(1,"hold snapshots or actual onset accounting failed: %d %d %d",ended[0]-started[0],ended[1]-started[1],ended[2]-started[2]);
  repeat(10000)@(posedge valid);
  if(active!==0)$fatal(1,"release not silent");
  for(kind=0;kind<4;kind++)for(note=36;note<=60;note+=12)for(velocity=48;velocity<=96;velocity+=48)begin
   hold_samples={32'd48000,32'd48000};cfg(0,note,kind,velocity,1);
   if(note!=60 || velocity!=96)repeat(1000)@(posedge valid);
   for(j=0;j<(note==60 && velocity==96 ? 48000 : 8192);j++)begin @(posedge valid);#1;
    if($isunknown(pcm[15:0]))$fatal(1,"unknown PCM");
    $fwrite(file,"%d,%d,%d,%d,%d\n",kind,note,velocity,j,$signed(pcm[15:0]));
   end
   cfg(0,note,kind,velocity,0);repeat(10000)@(posedge valid);
  end
  if(underflows!=0 || max_cycles>=200)$fatal(1,"renderer overrun %d %d",underflows,max_cycles);
  $display("TB_PASS hold100ms/1s/5s immutable; four timbres C2/C3/C4 velocity48/96; max=%d",max_cycles);
  $fclose(file);$finish;
 end
 initial begin #2000000000;$fatal(1,"watchdog");end
endmodule
