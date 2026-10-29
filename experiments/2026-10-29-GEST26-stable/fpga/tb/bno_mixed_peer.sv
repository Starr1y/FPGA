`timescale 1ns/1ps
// Wire peer follows SHTP v1.10: probe STOP produces continuation bit
// and incremented sequence; 100us INT turnaround before the cargo read.
// Does not inspect the FPGA FSM or any internal registers.
module bno_mixed_peer(input sensor_rst_n,inout scl,sda,output int_n,output reg configured);
 reg pull_sda=0,pull_scl=0;
 assign sda=pull_sda ? 1'b0 : 1'bz;assign scl=pull_scl ? 1'b0 : 1'bz;
 reg [4095:0] queue[0:31];integer head=0,tail=0;reg [7:0] seq2=0,seq3=0;
 integer commands=0,probes=0,transfers=0;reg nack_address=0,nack_payload=0;
 integer stretch_ns=0;reg corrupt_header=0;reg ready=1;reg early;integer nack_cargo_once=0;reg cargo_nak;
 reg [1:0] pose_accuracy=3,accel_accuracy=3,gyro_accuracy=3;reg [7:0] linear_seq=0,pose_seq=0;
 assign int_n=(head!=tail && sensor_rst_n && ready) ? 0 : 1;
 task enqueue(input [4095:0] p);begin queue[tail%32]=p;tail++;end endtask
 task boot;reg [4095:0] p;begin
  head=0;tail=0;commands=0;probes=0;transfers=0;configured=0;ready=1;seq2=0;seq3=0;linear_seq=0;pose_seq=0;p=0;p[7:0]=5;p[23:16]=1;p[39:32]=1;enqueue(p);
 end endtask
 initial begin configured=0;end
 always @(posedge sensor_rst_n)boot();
 task receive_byte(output reg [7:0] b);integer k;begin
  b=0;for(k=7;k>=0;k--)begin @(posedge scl);b[k]=sda;end
 end endtask
 task send_ack(input reg yes);begin
  @(negedge scl);pull_sda=yes;@(posedge scl);@(negedge scl);pull_sda=0;
 end endtask
 task send_byte(input [7:0] b,output reg a);integer k;begin
  for(k=7;k>=0;k--)begin
   @(negedge scl);pull_sda=!b[k];
   if(stretch_ns>0 && k==6)begin pull_scl=1;#(stretch_ns);pull_scl=0;end
   @(posedge scl);
  end
  @(negedge scl);pull_sda=0;@(posedge scl);a=!sda;
  // Leave the following falling edge for the caller's next byte.
 end endtask
 task feature_ack(input [7:0] id);reg [4095:0] p;begin
  p=0;p[7:0]=21;p[23:16]=2;p[31:24]=seq2;seq2+=2;p[39:32]=8'hfc;p[47:40]=id;p[103:72]=interval_for(id);enqueue(p);
 end endtask
 function [31:0] interval_for(input [7:0] id);
 begin case(id)8:interval_for=5000;1,6:interval_for=20000;2:interval_for=5000;4:interval_for=2500;default:interval_for=0;endcase end
 endfunction
 reg[7:0] gyro_seq=0,raw_seq=0,gravity_seq=0;
 realtime created[0:31];realtime max_transfer=0;
 task mixed_report(input integer tick,input signed[15:0] z_accel);
 reg[4095:0] p;integer n;
 begin
  if(tail!=head)$fatal(1,"report backlog at tick %d",tick);
  p=0;n=9;p[23:16]=3;p[31:24]=seq3;seq3+=2;p[39:32]=8'hfb;
  // Prioritize the time-critical linear report within the SHTP packet.
  p[n*8+:8]=4;p[(n+1)*8+:8]=linear_seq;linear_seq++;p[(n+2)*8+:8]=3;p[(n+8)*8+:16]=z_accel;n+=10;
  if(tick%2==0)begin
   p[n*8+:8]=8;p[(n+1)*8+:8]=pose_seq;pose_seq++;p[(n+2)*8+:8]=3;p[(n+10)*8+:16]=16384;n+=12;
   p[n*8+:8]=2;p[(n+1)*8+:8]=gyro_seq;gyro_seq++;p[(n+2)*8+:8]=3;n+=10;
  end
  if(tick%8==0)begin
   p[n*8+:8]=1;p[(n+1)*8+:8]=raw_seq;raw_seq++;p[(n+2)*8+:8]=3;p[(n+8)*8+:16]=2510;n+=10;
   p[n*8+:8]=6;p[(n+1)*8+:8]=gravity_seq;gravity_seq++;p[(n+2)*8+:8]=3;p[(n+8)*8+:16]=2510;n+=10;
  end
  p[15:0]=n;created[tail%32]=$realtime;enqueue(p);
 end endtask
 reg [7:0] address,b;reg a;reg [4095:0] p,rx;
 integer n,len,k;reg stop_read;
 initial forever begin
  @(negedge sda);
  if(scl===1 && sensor_rst_n)begin
   early=!ready;receive_byte(address);
   cargo_nak=address[0] && head!=tail && queue[head%32][15] && nack_cargo_once>0;
   if(cargo_nak)nack_cargo_once--;
   if(address[7:1]!=7'h4a || nack_address || (early && address[0]) || cargo_nak)begin send_ack(0);@(posedge sda);end
   else begin
    send_ack(1);
    if(address[0])begin
     p=head!=tail ? queue[head%32] : 0;len=p[15:0]&16'h7fff;n=0;stop_read=0;
     while(!stop_read)begin
      // ACK procedure already consumed one falling edge. Set the first
      // data bit now; subsequent bits use falling edges.
      b=corrupt_header && n<2 ? 8'hff : p[n*8+:8];pull_sda=!b[7];@(posedge scl);
      for(k=6;k>=0;k--)begin @(negedge scl);pull_sda=!b[k];
       if(stretch_ns>0 && k==6)begin pull_scl=1;#(stretch_ns);pull_scl=0;end
       @(posedge scl);
      end
      @(negedge scl);pull_sda=0;@(posedge scl);a=!sda;n++;
      @(negedge scl);
      if(!a)stop_read=1;
     end
     if(n==4)begin
      probes++;if(head!=tail && !corrupt_header)begin
       queue[head%32][15]=1;queue[head%32][31:24]=queue[head%32][31:24]+1;
      end
     end
     else if(n==len && head!=tail)begin if(p[23:16]==3 && $realtime-created[head%32]>max_transfer)max_transfer=$realtime-created[head%32];head++;transfers++;end
     else $fatal(1,"I2C peer read wrong count %d expected probe4/full%d",n,len);
     @(posedge sda);ready<=0;ready<=#100000 1;
    end else begin
     rx=0;n=0;len=2;
     while(n<len)begin receive_byte(b);rx[n*8+:8]=b;send_ack(!nack_payload);n++;
      if(n==2)begin len=rx[15:0];if(len<4 || len>21)$fatal(1,"host sent invalid length");end
      if(nack_payload)n=len;
     end
     if(!nack_payload)begin
      if(rx[23:16]!=2)$fatal(1,"write channel must be control");
      if(rx[39:32]==8'hfd)begin
       if(rx[47:40]!=8 && rx[47:40]!=1 && rx[47:40]!=2 && rx[47:40]!=4 && rx[47:40]!=6)
        $fatal(1,"six-axis profile requested an unexpected sensor ID");
       if(rx[103:72]!=interval_for(rx[47:40]))$fatal(1,"wrong mixed feature interval id=%h got=%d",rx[47:40],rx[103:72]);
       feature_ack(rx[47:40]);
      end else if(rx[39:32]!=8'hf9 && rx[39:32]!=8'hfe)$fatal(1,"unexpected SH2 command");
      commands++;if(commands==11)configured=1;
     end
     @(posedge sda);
    end
   end
  end
 end
endmodule
