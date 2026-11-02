`timescale 1ns/1ps
module tb_wrist_vibrato;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,clear=0,enabled=1,invert=0,button_n=1,pose_valid=0,playable=1,hit=0;
 reg signed[15:0]pitch=0;wire pressed,fresh;wire[1:0]octave,snapshot;wire signed[15:0]bend;wire[15:0]serial;
 wrist_gesture #(.CLK_HZ(1000)) d(clk,rst_n,clear,enabled,invert,button_n,pose_valid,playable,pitch,4'b0,1'b1,hit,4'b0,2'b0,2'b0,1'b0,pressed,octave,fresh,snapshot,bend,serial,);
 integer i,f,crossings,peak;reg positive;
 task advance(input integer n);integer t;begin for(t=0;t<n;t=t+1)begin @(negedge clk);pose_valid=(t%5)==0;end end endtask
 initial begin
  #12;rst_n=1;advance(100);button_n=0;advance(25);hit=1;@(negedge clk);hit=0;
  for(f=3;f<=9;f=f+3)begin
   crossings=0;peak=0;positive=0;
   for(i=0;i<1200;i=i+1)begin
    @(negedge clk);pose_valid=i%5==0;pitch=$rtoi(16.0*$sin(6.283185307*f*i/1000.0));
    if(i>200)begin
     if(bend>8 && !positive)begin positive=1;crossings++;end
     else if(bend< -8)positive=0;
     if(bend>peak)peak=bend;
    end
   end
   if(crossings<f-1 || crossings>f+1 || peak<15 || peak>45)$fatal(1,"motion vibrato freq%d crossings%d peak%d",f,crossings,peak);
  end
  pose_valid=1;pitch=0;advance(200);if(bend>2 || bend< -2)$fatal(1,"no self oscillation");
  $display("TB_PASS direct3/6/9Hz motion vibrato, bounded depth, no free LFO");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
