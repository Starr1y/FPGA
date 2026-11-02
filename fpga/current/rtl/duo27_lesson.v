module duo27_lesson #(parameter CLK_HZ=50000000)(
 input clk,rst_n,enabled,restart,clear_feedback,input[1:0]song,
 input hit,hand,input[6:0]note,input[3:0]zone,
 input score_loaded,input[11:0]score_total,input[31:0]score_word,output[10:0]score_address,
 output[11:0]position,output[15:0]correct,wrong,output target_hand,output[6:0]target_note,output[3:0]target_zone,
 output[1:0]target_octave,output[15:0]hold_ms,output[31:0]hold_samples,output target_ready,finished,last_correct,
 output[1:0]feedback,output feedback_hand,output[3:0]feedback_zone,output[15:0]event_serial);
 wire custom=song==3;
 wire[4:0]bp;wire[15:0]bc,bw,bs;wire bh,bf,bl,bfh;wire[6:0]bn;wire[3:0]bz,bfz;wire[1:0]bfeed;
 wire[11:0]cp;wire[15:0]cc,cw,cs;wire ch,cf,cl,cfh,ready;wire[6:0]cn;wire[3:0]cz,cfz;wire[1:0]cfeed,co;
 wire[15:0]hm;wire[31:0]hs;
 duo04_lesson #(.CLK_HZ(CLK_HZ)) builtin(.clk(clk),.rst_n(rst_n),.enabled(enabled && !custom),.restart(restart),.clear_feedback(clear_feedback),.song(song),
 .hit(hit),.hand(hand),.note(note),.zone(zone),.position(bp),.correct(bc),.wrong(bw),.target_hand(bh),.target_note(bn),.target_zone(bz),
 .finished(bf),.last_correct(bl),.feedback(bfeed),.feedback_hand(bfh),.feedback_zone(bfz),.event_serial(bs));
 score_lesson #(.CLK_HZ(CLK_HZ)) uploaded(.clk(clk),.rst_n(rst_n),.enabled(enabled && custom),.restart(restart),.clear_feedback(clear_feedback),
 .loaded(score_loaded),.total(score_total),.ram_word(score_word),.ram_address(score_address),.hit(hit),.hand(hand),.note(note),.zone(zone),
 .position(cp),.correct(cc),.wrong(cw),.target_hand(ch),.target_note(cn),.target_zone(cz),.target_octave(co),.hold_ms(hm),.hold_samples(hs),
 .target_ready(ready),.finished(cf),.last_correct(cl),.feedback(cfeed),.feedback_hand(cfh),.feedback_zone(cfz),.event_serial(cs));
 assign position=custom ? cp : {7'b0,bp};assign correct=custom ? cc : bc;assign wrong=custom ? cw : bw;
 assign target_hand=custom ? ch : bh;assign target_note=custom ? cn : bn;assign target_zone=custom ? cz : bz;
 assign target_octave=custom ? co : 2'b0;assign hold_ms=custom ? hm : 16'd500;assign hold_samples=custom ? hs : 32'd24000;assign target_ready=!custom || ready;
 assign finished=custom ? cf : bf;assign last_correct=custom ? cl : bl;assign feedback=custom ? cfeed : bfeed;
 assign feedback_hand=custom ? cfh : bfh;assign feedback_zone=custom ? cfz : bfz;assign event_serial=custom ? cs : bs;
endmodule
