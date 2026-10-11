`timescale 1ns/1ps
module tb_two_hand_queue;
 parameter DEPTH=8;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;
 reg[1:0]push_valid=0,cancel=0,release_ack=0;reg[63:0]push_payload=0;reg event_ready=0;
 wire[1:0]release_pending,accepted;wire[63:0]epochs,event_data,drops,cancelled_events;wire event_valid;
 two_hand_event_queue #(.DEPTH(DEPTH)) dut(.*);
 reg[63:0]reference0[0:8191],reference1[0:8191];integer rd[0:1],wr[0:1],epoch[0:1],drop[0:1],purged[0:1];
 reg[1:0]pending=0;reg[31:0]random_state=32'h92c172d1;
 integer cycles=0,transfers=0,side,expected_valid,expected_accept0,expected_accept1;
 integer held_side=-1;reg[63:0]held_data;integer length0,length1;
 always @(posedge clk)begin
  if(!rst_n)begin
   for(integer h=0;h<2;h++)begin rd[h]=0;wr[h]=0;epoch[h]=0;drop[h]=0;purged[h]=0;end
   pending=0;held_side=-1;
  end else begin
   length0=wr[0]-rd[0];length1=wr[1]-rd[1];
   expected_valid=(length0>0 && !pending[0] && !cancel[0]) || (length1>0 && !pending[1] && !cancel[1]);
   if(event_valid!==expected_valid[0] || release_pending!==pending)$fatal(1,"availability or release ownership differs");
   side=event_valid ? event_data[29] : -1;
   if(event_valid)begin
    if(pending[side] || cancel[side] || wr[side]==rd[side])$fatal(1,"invalid hand selected");
    if(event_data !== (side ? reference1[rd[1]] : reference0[rd[0]]))$fatal(1,"event reordered/corrupted side=%0d",side);
   end
   if(held_side>=0 && !cancel[held_side] && (!event_valid || event_data!==held_data))$fatal(1,"stalled event changed");
   held_side=event_valid && !event_ready ? side : -1;held_data=event_data;
   expected_accept0=push_valid[0] && !cancel[0] && (length0<DEPTH || (event_valid && event_ready && side==0));
   expected_accept1=push_valid[1] && !cancel[1] && (length1<DEPTH || (event_valid && event_ready && side==1));
   if(accepted!=={expected_accept1[0],expected_accept0[0]})$fatal(1,"enqueue admission mismatch");
   for(integer h=0;h<2;h++)begin
    if(release_ack[h])pending[h]=0;
    if(cancel[h])begin
     purged[h]+=wr[h]-rd[h];rd[h]=wr[h];epoch[h]++;pending[h]=1;
    end else begin
     if(event_valid && event_ready && side==h)begin rd[h]++;transfers++;end
     if(h ? expected_accept1 : expected_accept0)begin
      if(h)reference1[wr[h]]={epoch[h][31:0],push_payload[63:32]};else reference0[wr[h]]={epoch[h][31:0],push_payload[31:0]};wr[h]++;
     end else if(push_valid[h])drop[h]++;
    end
   end
   #1;
   if(epochs!=={epoch[1][31:0],epoch[0][31:0]} || drops!=={drop[1][31:0],drop[0][31:0]} ||
      cancelled_events!=={purged[1][31:0],purged[0][31:0]} || release_pending!==pending)$fatal(1,"accounting mismatch");
   cycles++;
  end
 end
 task tick;@(negedge clk);endtask
 task words(input integer n);begin push_payload={32'h20000000|n,32'h00000000|n};end endtask
 integer before_transfers;
 initial begin
  repeat(4)tick();rst_n=1;tick();
  // Two simultaneous producers fill independent queues; overflow is counted, not silently lost.
  push_valid=3;event_ready=0;for(integer n=0;n<DEPTH+3;n++)begin words(n);tick();end
  push_valid=0;event_ready=1;repeat(DEPTH*2+2)tick();
  if(drop[0]!=3 || drop[1]!=3 || transfers!=DEPTH*2)$fatal(1,"simultaneous capacity test");
  // A cancelled hand cannot block the healthy queue, even without a release ACK.
  event_ready=0;push_valid=3;words(99);tick();push_valid=0;cancel=1;release_ack=1;tick();cancel=0;release_ack=0;
  if(!release_pending[0])$fatal(1,"cancel must win simultaneous ACK");
  event_ready=1;before_transfers=transfers;repeat(4)tick();
  if(transfers!=before_transfers+1 || event_data[29]===1'b0 && event_valid)$fatal(1,"healthy hand blocked by release pending");
  // New epoch events wait only for their own group release; ACK makes them eligible.
  push_valid=1;words(101);tick();push_valid=0;repeat(3)tick();
  if(event_valid)$fatal(1,"new hand event escaped group-release barrier");
  release_ack=1;tick();release_ack=0;repeat(3)tick();
  for(integer n=0;n<2500;n++)begin
   random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   push_valid=random_state[1:0];event_ready=random_state[2];
   cancel=(random_state[9:3]==0) ? random_state[11:10] : 0;release_ack=random_state[13:12];words(n+200);tick();
  end
  push_valid=0;cancel=0;release_ack=3;event_ready=1;repeat(DEPTH*2+4)tick();
  if(event_valid || wr[0]!=rd[0] || wr[1]!=rd[1] || transfers<300)$fatal(1,"random test did not drain");
  $display("TB_PASS depth=%0d independent queues, simultaneous hits, stall stability, wrap, overflow accounting, cancel/ACK priority, healthy-hand progress, epochs; %0d transfers in %0d cycles",DEPTH,transfers,cycles);$finish;
 end
endmodule
