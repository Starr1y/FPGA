`timescale 1ns/1ps
module tb_wrist_audio;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,sample_tick=0;integer fraction=0;
 always @(posedge clk)begin sample_tick<=0;if(rst_n)begin if(fraction>=49952000)begin fraction<=fraction+48000-50000000;sample_tick<=1;end else fraction<=fraction+48000;end end
 reg ev=0;wire ready;reg[63:0]data=0;reg[1:0]pressed=0,presets_hold=0;reg[5:0]presets=0;reg[31:0]bend=0;
 wire[31:0]active,gates,underflows;wire valid,committed;wire signed[15:0]left,right;wire[15:0]max_render;
 two_hand_synth #(.VOICES(32),.ENABLE_EXPRESSION(1)) dut(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(ev),.event_ready(ready),.event_data(data),
 .release_pending(2'b0),.epochs(64'b0),.chord_mode(1'b0),.preset_ids(presets),.release_ids(4'b0),.hold_samples_left(32'd48),.hold_samples_right(32'd48),
 .piano_hold(2'b0),.piano_coefficients({16'd134,16'd134}),.bend_cents(0),.vibrato_cents(0),.brightness(16'h8080),.glide_coefficients(48'b0),.vibrato_ratios({20'd65536,20'd65536}),
 .wrist_enabled(2'b11),.wrist_pressed(pressed),.wrist_bend(bend),.active_voices(active),.gates(gates),.underflows(underflows),.committed(committed),.sample_valid(valid),.max_render_cycles(max_render),.stereo_left(left),.stereo_right(right),.monitor_voice(5'd0));
 integer f,frames=0,kind,i;reg[31:0]phase_old;reg[31:0]old_noise;
 always @(posedge valid)begin frames++;$fwrite(f,"%d %d\n",left,right);end
 task strike(input integer id);begin
  @(negedge clk);while(!ready)@(negedge clk);data=0;data[22:21]=3;data[20:14]=64;data[11:4]=id;ev=1;@(negedge clk);ev=0;wait(committed);@(negedge clk);
 end endtask
 initial begin
  f=$fopen("wrist_audio.txt","w");repeat(10)@(negedge clk);rst_n=1;
  for(kind=0;kind<4;kind++)begin
   presets=kind;pressed=1;bend=0;strike(kind+1);repeat(200)@(posedge valid);
   if(gates==0)$fatal(1,"hold timer expired while held");
   phase_old=dut.audio.phase[0];bend=600;repeat(350)@(posedge valid);
   if(dut.audio.phase[0]==phase_old || underflows)$fatal(1,"phase or underrun");
   bend=16'hfda8;repeat(350)@(posedge valid); // -600 cents
   if(kind==3 && dut.audio.models.seed_words[0]>800)$fatal(1,"pluck delay budget");
   pressed=0;repeat(300)@(posedge valid);if(gates!=0)$fatal(1,"release key did not release");
   repeat(10000)@(posedge valid);
  end
  if(underflows || max_render>=1040)$fatal(1,"render budget %d",max_render);
  $display("TB_PASS four timbres held beyond timer, bend updates, release and PCM; max %d",max_render);$fclose(f);$finish;
 end
 initial begin #1500000000;$fatal(1,"timeout");end
endmodule
