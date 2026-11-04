`timescale 1ns/1ps
module tb_chord32;
reg clk=0;always #10 clk=~clk;
reg rst_n=0,ev=0,chord=0;reg[63:0]data=0;wire ready,cfg;wire[127:0]cfgdata;wire[31:0]owned,gates;reg[511:0]env;integer k;always @*for(k=0;k<32;k=k+1)env[k*16+:16]=gates[k] ? 16'd32768 : 16'd0;wire[223:0]notes;
dual_voice_scheduler #(.VOICES(32)) d(.clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready),.event_data(data),
.release_pending(2'b0),.epochs(64'b0),.chord_mode(chord),.preset_ids(6'b0),.release_ids(4'b0),.hold_ticks_left(0),.hold_ticks_right(0),
.mono_glide(2'b0),.bend_cents(0),.vibrato_cents(0),.brightness(16'h8080),.legato_enable(2'b0),.envelopes(env),.release_due(32'b0),
.config_valid(cfg),.config_data(cfgdata),.config_ready(1'b1),.owned(owned),.gates(gates),.notes(notes),.wrist_enabled(2'b0),.wrist_pressed(2'b0),.wrist_bend(0));
integer starts=0;
always @(posedge clk)if(!rst_n)starts<=0;else if(cfg && cfgdata[58])starts<=starts+1;
task reset;begin rst_n=0;repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);end endtask
task hit(input integer hand,zone,profile,oct);begin
 @(negedge clk);while(!ready)@(negedge clk);
 data=0;data[29]=hand;data[28:25]=zone;data[24:23]=profile;data[22:21]=oct;data[20:14]=80;data[11:4]=1;ev=1;
 @(negedge clk);ev=0;repeat(300)@(negedge clk);
end endtask
task triad(input integer zone,profile,oct,a,b,c);begin
 reset();chord=1;hit(0,zone,profile,oct);
 if($countones(owned)!=3 || starts!=3 || notes[6:0]!=a || notes[13:7]!=b || notes[20:14]!=c)
  $fatal(1,"chord allocation profile%0d zone%0d notes%h starts%0d",profile,zone,notes,starts);
 hit(1,0,0,0);
 if($countones(owned[15:0])!=3 || $countones(owned[31:16])!=1 || starts!=4 || notes[112+:7]!=60)$fatal(1,"right hand not single");
end endtask
initial begin
 reset();chord=0;hit(0,0,0,0);if($countones(owned)!=1 || starts!=1 || notes[6:0]!=60)$fatal(1,"single mode");
 triad(0,0,0,60,64,67);triad(1,0,0,62,65,69);triad(6,0,0,71,74,77);
 triad(0,0,3,48,52,55);triad(0,0,1,72,76,79);
 triad(1,1,0,62,66,69);triad(1,2,0,61,65,68);
 $display("TB_PASS left single/3voice diatonic triads,C3/C4/C5,pentatonic/chromatic major triads,right always single");$finish;
end
initial begin #2000000;$fatal(1,"watchdog");end
endmodule
