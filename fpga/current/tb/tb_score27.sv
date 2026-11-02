`timescale 1ns/1ps
module tb_score27;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,abort=0,command=0,playing=0,enabled=0,restart=0,clear_feedback=0,hit=0,hand=0;
 reg[6:0]note=36;reg[3:0]zone=0;reg[7:0]kind=0;reg[6:0]length=0;reg[511:0]payload=0;
 wire ack,busy,uploading,loaded,committed;wire[7:0]code;wire[31:0]tid,active_crc,ram_word,readback;
 wire[11:0]uploaded,total,position;wire[1:0]profile,octave,feedback;wire[15:0]rev,rr,correct,wrong,hold_ms,serial;
 wire[10:0]address,ri;wire th,ready,finished,lc,fh;wire[6:0]tn;wire[3:0]tz,fz;wire[31:0]hold_samples;
 score_store store(.clk(clk),.rst_n(rst_n),.abort(abort),.playing(playing),.command(command),.kind(kind),.length(length),.payload(payload),
 .ack(ack),.code(code),.busy(busy),.uploading(uploading),.loaded(loaded),.committed(committed),.transfer_id(tid),.active_crc(active_crc),.uploaded(uploaded),.total(total),.profile(profile),.revision(rev),
 .read_address(address),.read_word(ram_word),.readback_index(ri),.readback_word(readback),.readback_revision(rr));
 score_lesson #(.CLK_HZ(1000)) lesson(.clk(clk),.rst_n(rst_n),.enabled(enabled),.restart(restart),.clear_feedback(clear_feedback),.loaded(loaded),.total(total),.ram_word(ram_word),.ram_address(address),
 .hit(hit),.hand(hand),.note(note),.zone(zone),.position(position),.correct(correct),.wrong(wrong),.target_hand(th),.target_note(tn),.target_zone(tz),.target_octave(octave),.hold_ms(hold_ms),.hold_samples(hold_samples),
 .target_ready(ready),.finished(finished),.last_correct(lc),.feedback(feedback),.feedback_hand(fh),.feedback_zone(fz),.event_serial(serial));
 localparam[31:0] A=32'h01f4480a,B=32'h03e89316,CRC=32'hb5ecacb4,MAXCRC=32'h83880f6c;
 task send(input[7:0]k,input[6:0]n,input[511:0]v,input[7:0]expected);integer timeout;begin
  @(negedge clk);kind=k;length=n;payload=v;command=1;@(negedge clk);command=0;timeout=0;
  while(!ack)begin @(negedge clk);timeout=timeout+1;if(timeout>2000)$fatal(1,"ACK timeout");end
  if(code!==expected)$fatal(1,"command %d code %d expected%d",k,code,expected);
  @(negedge clk);
 end endtask
 task begin_upload(input[31:0]id,input[15:0]count,input[31:0]crc);reg[511:0]v;begin v=0;v[31:0]=id;v[39:32]=2;v[55:40]=count;v[87:56]=crc;send(69,11,v,0);end endtask
 task strike(input h,input[6:0]n,input[3:0]z);begin @(negedge clk);hand=h;note=n;zone=z;hit=1;@(negedge clk);hit=0;end endtask
 reg[511:0]v;integer i,j,n;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  send(73,2,0,2);begin_upload(7,2,CRC);
  v=0;v[31:0]=7;v[55:48]=2;v[87:56]=A;v[119:88]=B;send(70,15,v,0);
  if(uploaded!=2 || loaded)$fatal(1,"staging published early");
  send(70,15,v,0);if(uploaded!=2)$fatal(1,"duplicate changed progress");
  v[88]=!v[88];send(70,15,v,2);v[88]=!v[88];send(71,4,7,0);
  if(!loaded || total!=2 || active_crc!=CRC)$fatal(1,"commit");
  send(73,2,1,0);if(readback!=B)$fatal(1,"RAM readback");
  playing=1;send(73,2,0,3);playing=0;
  restart=1;@(negedge clk);restart=0;repeat(8)@(negedge clk);enabled=1;
  if(!ready || tn!=36 || th || octave!=2 || hold_samples!=24000)$fatal(1,"first target");
  strike(1,36,0);if(wrong!=1 || position!=0)$fatal(1,"wrong hand");
  strike(0,36,0);strike(0,36,0);if(correct!=1 || feedback!=1)$fatal(1,"repeat during feedback");
  enabled=0;repeat(400)@(negedge clk);if(position!=0)$fatal(1,"pause progressed");
  enabled=1;repeat(260)@(negedge clk);if(position!=1 || tn!=73 || !th || octave!=1 || hold_samples!=48000)$fatal(1,"second target/auto octave");
  strike(1,73,1);repeat(260)@(negedge clk);if(!finished || correct!=2 || position!=2)$fatal(1,"finish");
  repeat(300)@(negedge clk);if(position!=2)$fatal(1,"auto loop");
  enabled=0;begin_upload(8,2,0);v=0;v[31:0]=8;v[55:48]=2;v[87:56]=A;v[119:88]=B;send(70,15,v,0);send(71,4,8,2);
  if(active_crc!=CRC || !loaded)$fatal(1,"failed commit replaced old song");
  abort=1;@(negedge clk);abort=0;if(uploading)$fatal(1,"abort");
  begin_upload(9,2048,MAXCRC);
  for(i=0;i<2048;i=i+12)begin
   n=2048-i;if(n>12)n=12;v=0;v[31:0]=9;v[47:32]=i;v[55:48]=n;
   for(j=0;j<n;j=j+1)v[56+j*32+:32]=A;send(70,7+n*4,v,0);
  end
  send(71,4,9,0);send(73,2,2047,0);if(total!=2048 || readback!=A)$fatal(1,"2048 last step");
  restart=1;@(negedge clk);restart=0;repeat(8)@(negedge clk);if(position!=0 || finished)$fatal(1,"restart");
  $display("TB_PASS score dual-bank upload/duplicate/mismatch/CRC rollback/2048 readback; lesson hand/octave/pause/finish/restart");$finish;
 end
 initial begin #10000000;$fatal(1,"watchdog");end
endmodule
