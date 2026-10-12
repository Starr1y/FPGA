// Independent queues prevent a blocked/cancelled hand from stopping the other.
// Cancellation purges only that hand and remains pending until group-release ACK.
module two_hand_event_queue #(parameter DEPTH=8)(
 input clk,rst_n,input[1:0]push_valid,input[63:0]push_payload,
 input[1:0]cancel,release_ack,output reg[1:0]release_pending,
 output[63:0]epochs,output event_valid,input event_ready,output[63:0]event_data,
 output reg[63:0]drops,cancelled_events,output[1:0]accepted
);
 localparam PTR_BITS=$clog2(DEPTH)>0 ? $clog2(DEPTH) : 1;
 localparam COUNT_BITS=$clog2(DEPTH+1);
 reg[63:0]mem0[0:DEPTH-1],mem1[0:DEPTH-1];
 reg[PTR_BITS-1:0]rd0,rd1,wr0,wr1;
 reg[COUNT_BITS-1:0]count0,count1;
 reg[31:0]epoch0,epoch1;reg prefer1,locked,locked_hand;
 wire eligible0=count0!=0 && !release_pending[0] && !cancel[0];
 wire eligible1=count1!=0 && !release_pending[1] && !cancel[1];
 wire selected=locked && (locked_hand ? eligible1 : eligible0) ? locked_hand : eligible0 && eligible1 ? prefer1 : eligible1;
 assign event_valid=eligible0 || eligible1;
 assign event_data=selected ? mem1[rd1] : mem0[rd0];
 assign epochs={epoch1,epoch0};
 wire pop0=event_valid && event_ready && !selected;
 wire pop1=event_valid && event_ready && selected;
 assign accepted[0]=push_valid[0] && !cancel[0] && (count0<DEPTH || pop0);
 assign accepted[1]=push_valid[1] && !cancel[1] && (count1<DEPTH || pop1);
 function[PTR_BITS-1:0] advance;
 input[PTR_BITS-1:0]ptr;begin advance=ptr==DEPTH-1 ? 0 : ptr+1'b1;end
 endfunction
 function[31:0]satadd;
 input[31:0]a,b;reg[32:0]sum;begin sum={1'b0,a}+{1'b0,b};satadd=sum[32] ? 32'hffffffff : sum[31:0];end
 endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   rd0<=0;rd1<=0;wr0<=0;wr1<=0;count0<=0;count1<=0;
   epoch0<=0;epoch1<=0;release_pending<=0;drops<=0;cancelled_events<=0;prefer1<=0;locked<=0;locked_hand<=0;
  end else begin
   if(event_valid && !event_ready)begin locked<=1;locked_hand<=selected;end
   else locked<=0;
   if(event_valid && event_ready)prefer1<=!selected;
   if(release_ack[0])release_pending[0]<=0;
   if(release_ack[1])release_pending[1]<=0;
   if(cancel[0])begin
    rd0<=0;wr0<=0;count0<=0;epoch0<=epoch0+1'b1;release_pending[0]<=1;
    cancelled_events[31:0]<=satadd(cancelled_events[31:0],count0);
   end else begin
    case({accepted[0],pop0})2'b10:count0<=count0+1'b1;2'b01:count0<=count0-1'b1;default:;endcase
    if(accepted[0])begin mem0[wr0]<={epoch0,push_payload[31:0]};wr0<=advance(wr0);end
    if(pop0)rd0<=advance(rd0);
    if(push_valid[0] && !accepted[0])drops[31:0]<=satadd(drops[31:0],1);
   end
   if(cancel[1])begin
    rd1<=0;wr1<=0;count1<=0;epoch1<=epoch1+1'b1;release_pending[1]<=1;
    cancelled_events[63:32]<=satadd(cancelled_events[63:32],count1);
   end else begin
    case({accepted[1],pop1})2'b10:count1<=count1+1'b1;2'b01:count1<=count1-1'b1;default:;endcase
    if(accepted[1])begin mem1[wr1]<={epoch1,push_payload[63:32]};wr1<=advance(wr1);end
    if(pop1)rd1<=advance(rd1);
    if(push_valid[1] && !accepted[1])drops[63:32]<=satadd(drops[63:32],1);
   end
  end
 end
endmodule
