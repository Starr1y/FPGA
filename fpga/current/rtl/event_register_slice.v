// One event register with no combinational downstream-ready -> upstream-ready
// path. Epoch/cancel checks discard only the affected hand. Stop/source changes
// flush synchronously and suppress output immediately.
module event_register_slice(
 input clk,rst_n,flush,input[1:0]cancel,input[63:0]epochs,
 input in_valid,output in_ready,input[63:0]in_data,
 output out_valid,input out_ready,output[63:0]out_data);
 reg full;reg[63:0]data_q;
 wire match_left,match_right;
 epoch_match32 slice_left(data_q[63:32],epochs[31:0],match_left);
 epoch_match32 slice_right(data_q[63:32],epochs[63:32],match_right);
 wire dead=cancel[data_q[29]] || !(data_q[29] ? match_right : match_left);
 assign in_ready=!full && !flush;
 assign out_valid=full && !flush && !dead;
 assign out_data=data_q;
 always @(posedge clk)begin
  if(!rst_n || flush)begin full<=0;data_q<=0;end
  else if(full)begin if(dead || out_ready)full<=0;end
  else if(in_valid)begin data_q<=in_data;full<=1;end
 end
endmodule
