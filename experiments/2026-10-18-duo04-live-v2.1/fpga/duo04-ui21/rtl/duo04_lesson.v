module duo04_lesson #(parameter CLK_HZ=50000000,CORRECT_MS=250,WRONG_MS=180)(
 input clk,rst_n,enabled,restart,clear_feedback,input[1:0]song,input hit,hand,input[6:0]note,input[3:0]zone,
 output reg[4:0]position,output reg[15:0]correct,wrong,
 output target_hand,output[6:0]target_note,output[3:0]target_zone,
 output finished,output reg last_correct,output reg[1:0]feedback,
 output reg feedback_hand,output reg[3:0]feedback_zone,output reg[15:0]event_serial);
 reg[31:0]divider;reg[15:0]remaining;
 wire tick=divider==CLK_HZ/1000-1;
 wire[3:0]degree=position<8 ? position[3:0] : 15-position[3:0];
 assign target_zone=degree==7 ? 0 : degree;
 assign target_hand=song==0 ? 0 : song==1 ? 1 : position[0];
 reg[6:0]mapped;
 always @*case(target_zone)0:mapped=60;1:mapped=62;2:mapped=64;3:mapped=65;4:mapped=67;5:mapped=69;default:mapped=71;endcase
 assign target_note=mapped;assign finished=position==16;
 always @(posedge clk)begin
  if(!rst_n || restart)begin position<=0;correct<=0;wrong<=0;last_correct<=0;feedback<=0;feedback_hand<=0;feedback_zone<=0;remaining<=0;divider<=0;event_serial<=0;end
  else begin
   divider<=tick ? 0 : divider+1'b1;
   if(clear_feedback)begin if(feedback==1)position<=position+1'b1;feedback<=0;remaining<=0;end
   else if(enabled)begin
    if(feedback!=0 && tick)begin
     if(remaining<=1)begin
      if(feedback==1)position<=position+1'b1;
      feedback<=0;remaining<=0;
     end else remaining<=remaining-1'b1;
    end
    if(!finished && feedback!=1 && hit)begin
     feedback_hand<=hand;feedback_zone<=zone;event_serial<=event_serial+1'b1;
     if(hand==target_hand && note==target_note)begin correct<=correct+1'b1;last_correct<=1;feedback<=1;remaining<=CORRECT_MS;end
     else begin if(wrong!=65535)wrong<=wrong+1'b1;last_correct<=0;feedback<=2;remaining<=WRONG_MS;end
    end
   end
  end
 end
endmodule
