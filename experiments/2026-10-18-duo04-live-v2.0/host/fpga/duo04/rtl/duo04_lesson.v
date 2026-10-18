// Score events only, not audio samples. Wrong notes never advance the lesson.
module duo04_lesson(input clk,rst_n,enabled,restart,input[1:0]song,
 input hit,input hand,input[6:0]note,
 output reg[4:0]position,output reg[15:0]correct,wrong,
 output target_hand,output[6:0]target_note,output[3:0]target_zone,
 output finished,output reg last_correct);
 wire[3:0]degree=position<8 ? position[3:0] : 15-position[3:0];
 assign target_zone=degree==7 ? 0 : degree;
 assign target_hand=song==0 ? 0 : song==1 ? 1 : position[0];
 reg[6:0]mapped;
 always @*case(target_zone)
  0:mapped=60;1:mapped=62;2:mapped=64;3:mapped=65;
  4:mapped=67;5:mapped=69;default:mapped=71;
 endcase
 assign target_note=mapped;
 assign finished=position==16;
 always @(posedge clk)begin
  if(!rst_n || restart)begin position<=0;correct<=0;wrong<=0;last_correct<=0;end
  else if(enabled && !finished && hit)begin
   if(hand==target_hand && note==target_note)begin
    position<=position+1'b1;correct<=correct+1'b1;last_correct<=1;
   end else begin if(wrong!=65535)wrong<=wrong+1'b1;last_correct<=0;end
  end
 end
endmodule
