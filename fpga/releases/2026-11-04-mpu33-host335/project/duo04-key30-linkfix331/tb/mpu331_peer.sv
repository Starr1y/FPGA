`timescale 1ns/1ps
// Behavioral register slave. Uses only wire-level START/STOP/ACK edges.
module mpu331_peer #(parameter ADDRESS=7'h68,PERIOD_NS=100000,WHO=8'h68,DISABLE_DRDY=0)(inout scl,sda,input connected,
 input signed[15:0]ax,ay,az,gx,gy,gz,output reg configured=0,output interrupt);
 reg pull_sda=0;assign sda=pull_sda ? 1'b0 : 1'bz;
 reg[7:0]registers[0:255];integer i;reg[7:0]pointer=0,address_byte,byte_in,byte_out;reg accepted,restarted,master_ack;
 assign interrupt=connected && registers['h3a][0] && registers['h38][0];
 event start_event,stop_event;
 always @(negedge sda)if(scl===1 && !pull_sda)->start_event;
 always @(posedge sda)if(scl===1)->stop_event;
 initial begin for(i=0;i<256;i=i+1)registers[i]=0;registers['h75]=WHO;registers['h6b]='h40;end
 always begin #(PERIOD_NS);
  if(connected && registers['h6b]==1 && registers['h38]==1)begin
   configured=registers['h19]==4 && registers['h1a]==3 && registers['h1b]=='h10 && registers['h1c]=='h10;
   registers['h3a]=DISABLE_DRDY ? 0 : 1;
   {registers['h3b],registers['h3c]}=ax;{registers['h3d],registers['h3e]}=ay;{registers['h3f],registers['h40]}=az;
   {registers['h43],registers['h44]}=gx;{registers['h45],registers['h46]}=gy;{registers['h47],registers['h48]}=gz;
  end
 end
 task receive(output reg[7:0]value);integer k;begin for(k=7;k>=0;k=k-1)begin @(posedge scl);value[k]=sda;end end endtask
 task acknowledge(input yes);begin @(negedge scl);pull_sda=yes;@(posedge scl);@(negedge scl);pull_sda=0;end endtask
 task transmit(input[7:0]value,output reg yes);integer k;begin
  pull_sda=!value[7];@(posedge scl);
  for(k=6;k>=0;k=k-1)begin @(negedge scl);pull_sda=!value[k];@(posedge scl);end
  @(negedge scl);pull_sda=0;@(posedge scl);yes=!sda;@(negedge scl);
 end endtask
 initial forever begin
  @start_event;
  do begin
   restarted=0;
   fork:transaction
    begin
     receive(address_byte);accepted=connected && address_byte[7:1]==ADDRESS;acknowledge(accepted);
     if(accepted)begin
      if(address_byte[0])begin
       master_ack=1;
       while(master_ack)begin
        byte_out=registers[pointer];transmit(byte_out,master_ack);
        if(pointer=='h3a)registers['h3a]=0;
        pointer=pointer+1;
       end
       @stop_event;
      end else begin
       receive(pointer);acknowledge(1);
       forever begin
        receive(byte_in);registers[pointer]=byte_in;acknowledge(1);pointer=pointer+1;
       end
      end
     end else @stop_event;
    end
    begin @start_event;restarted=1;end
    begin @stop_event;end
   join_any
   disable transaction;pull_sda=0;
  end while(restarted);
 end
endmodule
