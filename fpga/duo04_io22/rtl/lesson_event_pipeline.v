// Observe accepted notes without extending the sensor-queue critical path into
// note mapping and lesson scoring. No audio event is delayed or consumed here.
module lesson_event_pipeline(
 input clk,rst_n,flush,accepted,input[63:0]event_data,epochs,
 output hit,output reg hand,output reg[6:0]note,output reg[3:0]zone);
 reg accepted_q,hit_q;
 reg[63:0]data_q;
 wire mapped_valid;wire[6:0]mapped_note;
 wire[31:0]current_epoch=data_q[29] ? epochs[63:32] : epochs[31:0];
 dual_note_map map(.profile(data_q[24:23]),.zone(data_q[28:25]),
  .octave(data_q[22:21]),.chord(1'b0),.member(2'b00),
  .valid(mapped_valid),.midi_note(mapped_note));
 assign hit=hit_q && !flush;
 always @(posedge clk)begin
  if(!rst_n || flush)begin accepted_q<=0;hit_q<=0;data_q<=0;hand<=0;note<=0;zone<=0;end
  else begin
   accepted_q<=accepted;
   if(accepted) data_q<=event_data;
   hit_q<=accepted_q && data_q[31:30]==0 && mapped_valid && data_q[63:32]==current_epoch;
   if(accepted_q)begin hand<=data_q[29];note<=mapped_note;zone<=data_q[28:25];end
  end
 end
endmodule
