`timescale 1ns/1ps
module tb_scheduler_equivalence;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,ev=0,cr=1;
 reg[63:0]data=0,epochs=64'hfffffff8_fffffff8;
 reg[1:0]release_pending=0,pressed=0;reg[31:0]bend=0,vibrato=0,wrbend=0;
 reg[511:0]envs=0;reg[31:0]due=0;reg[1:0]mono=0;
 wire ready_d,ready_r,cv_d,cv_r,commit_d,commit_r,hand_d,hand_r;
 wire[1:0]ack_d,ack_r;wire[127:0]cfg_d,cfg_r;
 wire[255:0]bright_d,bright_r;wire[31:0]owned_d,owned_r,gates_d,gates_r,hold_d,hold_r;
 wire[223:0]notes_d,notes_r;wire[31:0]invalid_d,invalid_r,stolen_d,stolen_r;wire[7:0]id_d,id_r;
 dual_voice_scheduler d(.clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready_d),.event_data(data),
 .release_pending(release_pending),.release_ack(ack_d),.epochs(epochs),.chord_mode(1'b1),.preset_ids(6'b011000),.release_ids(4'b0),
 .hold_ticks_left(0),.hold_ticks_right(0),.mono_glide(mono),.bend_cents(bend),.vibrato_cents(vibrato),.brightness(16'h8080),
 .wrist_enabled(2'b11),.wrist_pressed(pressed),.wrist_bend(wrbend),.envelopes(envs),.release_due(due),
 .config_valid(cv_d),.config_data(cfg_d),.config_ready(cr),.voice_brightness(bright_d),.owned(owned_d),.gates(gates_d),.notes(notes_d),
 .invalid_events(invalid_d),.stolen_notes(stolen_d),.wrist_hold(hold_d),.committed(commit_d),.committed_id(id_d),.committed_hand(hand_d));
 dual_voice_scheduler_v4_reference r(.clk(clk),.rst_n(rst_n),.event_valid(ev),.event_ready(ready_r),.event_data(data),
 .release_pending(release_pending),.release_ack(ack_r),.epochs(epochs),.chord_mode(1'b1),.preset_ids(6'b011000),.release_ids(4'b0),
 .hold_ticks_left(0),.hold_ticks_right(0),.mono_glide(mono),.bend_cents(bend),.vibrato_cents(vibrato),.brightness(16'h8080),
 .wrist_enabled(2'b11),.wrist_pressed(pressed),.wrist_bend(wrbend),.envelopes(envs),.release_due(due),
 .config_valid(cv_r),.config_data(cfg_r),.config_ready(cr),.voice_brightness(bright_r),.owned(owned_r),.gates(gates_r),.notes(notes_r),
 .invalid_events(invalid_r),.stolen_notes(stolen_r),.wrist_hold(hold_r),.committed(commit_r),.committed_id(id_r),.committed_hand(hand_r));
 integer k,i,h,events=0,cancels=0,commits=0,acks=0;reg[7:0]states=0;reg[31:0]a,b;wire eq;
 epoch_match32 cmp(a,b,eq);
 always @(posedge clk)begin #1;
  if({ready_d,cv_d,cfg_d,ack_d,owned_d,gates_d,notes_d,invalid_d,stolen_d,hold_d,commit_d,id_d,hand_d,bright_d} !==
     {ready_r,cv_r,cfg_r,ack_r,owned_r,gates_r,notes_r,invalid_r,stolen_r,hold_r,commit_r,id_r,hand_r,bright_r})$fatal(1,"scheduler observable mismatch at%0d",k);
  if(rst_n)begin
   states[d.alloc_state]=1;commits=commits+commit_d;acks=acks+ack_d[0]+ack_d[1];
   for(i=0;i<32;i=i+1)
    if({d.revision[i],d.epoch[i],d.ftw[i],d.ids[i],d.gain[i],d.voice_bend[i]} !==
       {r.revision[i],r.epoch[i],r.ftw[i],r.ids[i],r.gain[i],r.voice_bend[i]})$fatal(1,"voice state mismatch");
  end
 end
 initial begin
  a=0;b=0;#1;if(!eq)$fatal(1,"equal zero");
  for(k=0;k<32;k=k+1)begin a=0;b=32'b1<<k;#1;if(eq)$fatal(1,"dropped epoch bit");a=b;#1;if(!eq)$fatal(1,"equal bit");end
  repeat(8)@(negedge clk);rst_n=1;
  for(k=0;k<40000;k=k+1)begin
   @(negedge clk);
   a=$random;b=k%3==0 ? a : $random;#1;if(eq!==(a==b))$fatal(1,"32-bit comparator mismatch");
   cr=k%80<60;
   if(ev&&ready_d)ev=0;
   for(h=0;h<2;h=h+1)if(ack_d[h])release_pending[h]=0;
   if(k%1000==999)begin
    h=(k/1000)%2;release_pending[h]=1;epochs[h*32+:32]=epochs[h*32+:32]+1;events=events+1;cancels=cancels+1;
   end
   if(k%2000==10)begin pressed=$random;wrbend={$random,$random};bend=$random;vibrato=$random;mono=$random;end
   due=k%499==0 ? $random : 0;
   if(!ev&&ready_d&&k%13==0)begin
    h=$urandom_range(0,1);data=0;data[29]=h;
    data[63:32]=epochs[h*32+:32]-(k%7==0 ? 1 : 0);
    data[31:30]=k%5==0 ? 1 : 0;data[28:25]=$urandom_range(0,6);data[22:21]=$urandom_range(0,3);
    data[20:14]=$urandom_range(1,127);data[11:4]=events;ev=1;events=events+1;
   end
  end
  if(states!==8'hff||commits<10||acks<10)$fatal(1,"insufficient allocation/cancel coverage states=%h commits%0d acks%0d",states,commits,acks);
  $display("TB_PASS40000 cycle-exact scheduler comparisons, all8allocation states, full32epoch/wrap, stale events, cancel%0d ack%0d commit%0d and backpressure",cancels,acks,commits);$finish;
 end
endmodule
