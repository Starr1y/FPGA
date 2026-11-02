// Uploaded single-note lesson. RAM target/hold decode is registered before ready.
module score_lesson #(parameter CLK_HZ=50000000)(
 input clk,rst_n,enabled,restart,clear_feedback,loaded,input[11:0]total,
 input[31:0]ram_word,output[10:0]ram_address,
 input hit,hand,input[6:0]note,input[3:0]zone,
 output reg[11:0]position,output reg[15:0]correct,wrong,
 output reg target_hand,output reg[6:0]target_note,output reg[3:0]target_zone,output reg[1:0]target_octave,
 output reg[15:0]hold_ms,output reg[31:0]hold_samples,output target_ready,finished,
 output reg last_correct,output reg[1:0]feedback,output reg feedback_hand,output reg[3:0]feedback_zone,output reg[15:0]event_serial);
 reg[31:0]divider;reg[8:0]remaining;reg[2:0]load_wait;
 wire tick=divider==CLK_HZ/1000-1;
 wire at_end;
 unsigned_ge12 end_compare(position,total,at_end);
 assign ram_address=position[10:0];assign finished=loaded && at_end;
 assign target_ready=loaded && !finished && load_wait==0;
 always @(posedge clk)begin
  if(!rst_n || restart)begin
   position<=0;correct<=0;wrong<=0;feedback<=0;feedback_hand<=0;feedback_zone<=0;event_serial<=0;last_correct<=0;
   divider<=0;remaining<=0;load_wait<=4;target_hand<=0;target_note<=60;target_zone<=0;target_octave<=0;hold_ms<=500;hold_samples<=24000;
  end else begin
   divider<=tick ? 0 : divider+1'b1;
   if(load_wait!=0 && loaded)begin
    load_wait<=load_wait-1'b1;
    if(load_wait==2)begin target_hand<=ram_word[8];target_note<=ram_word[15:9];target_zone<=ram_word[7:4];target_octave<=ram_word[3:2];hold_ms<=ram_word[31:16];end
    if(load_wait==1)hold_samples<=({16'b0,hold_ms}<<5)+({16'b0,hold_ms}<<4);
   end
   if(clear_feedback)begin feedback<=0;remaining<=0;end
   else if(enabled && target_ready)begin
    if(feedback!=0 && tick)begin
     if(remaining<=1)begin
      if(feedback==1)begin position<=position+1'b1;load_wait<=4;end
      feedback<=0;remaining<=0;
     end else remaining<=remaining-1'b1;
    end
    if(!finished && feedback!=1 && hit)begin
     feedback_hand<=hand;feedback_zone<=zone;event_serial<=event_serial+1'b1;
     if(hand==target_hand && note==target_note)begin if(correct!=65535)correct<=correct+1'b1;feedback<=1;remaining<=250;last_correct<=1;end
     else begin if(wrong!=65535)wrong<=wrong+1'b1;feedback<=2;remaining<=180;last_correct<=0;end
    end
   end
  end
 end
endmodule

// Same full unsigned comparison, zero latency. Preserve4-bit Boolean leaves
// so the target-ready path cannot be rebuilt as a12-bit carry comparator.
module unsigned_ge12(input[11:0]a,b,output ge);
 wire[2:0]eq /* synthesis syn_keep=1 */;
 wire[2:0]gt /* synthesis syn_keep=1 */;
 genvar n;
 generate for(n=0;n<3;n=n+1)begin:nibbles
  assign eq[n]=a[n*4+:4]==b[n*4+:4];
  assign gt[n]=a[n*4+:4]>b[n*4+:4];
 end endgenerate
 assign ge=gt[2] || (eq[2] && (gt[1] || (eq[1] && (gt[0] || eq[0]))));
endmodule
