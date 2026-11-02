`timescale 1ns/1ps
module tb_epoch_compare;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;
 reg[63:0]event_data=0,epochs=0;integer i;reg[31:0]old_epoch;
 dual_voice_scheduler d(.clk(clk),.rst_n(rst_n),.event_valid(1'b0),.event_data(event_data),.epochs(epochs),.release_pending(2'b0));
 initial begin
  for(i=0;i<10000;i=i+1)begin
   @(negedge clk);epochs={$random,$random};event_data={$random,$random};
   if(i%3==0)event_data[63:32]=event_data[29] ? epochs[63:32] : epochs[31:0];
   d.pending=event_data;#1;
   old_epoch=event_data[29] ? epochs[63:32] : epochs[31:0];
   if(d.input_epoch_current!==(event_data[63:32]==old_epoch) || d.pending_epoch_current!==(event_data[63:32]==old_epoch))$fatal(1,"epoch compare differs");
  end
  $display("TB_PASS10000 full32-bit epochs, both bank selection paths, no latency change");$finish;
 end
endmodule
