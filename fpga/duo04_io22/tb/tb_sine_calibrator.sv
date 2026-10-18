`timescale 1ns/1ps
// Accelerated sample enable: 16 FPGA clocks/sample. DSP math and 48kHz DDS remain production.
module tb_sine_calibrator;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,sample_tick=0,enable=0;
 reg[31:0]frequency=89478485;reg[15:0]amplitude=1036;reg[1:0]channels=3;
 wire active,valid;wire signed[15:0]left,right;
 sine_calibrator dut(.*);
 integer file,k,samples=0;
 task sample;
 begin @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;repeat(14)@(negedge clk);end
 endtask
 always @(posedge clk)if(valid)begin
  $fwrite(file,"%d,%d,%d,%d\n",samples,left,right,dut.ramp);samples++;
 end
 initial begin
  file=$fopen("sine.csv","w");$fwrite(file,"sample,left,right,ramp\n");repeat(5)@(negedge clk);rst_n=1;enable=1;
  for(k=0;k<300000;k++)sample(); // 6.25 seconds at nominal 48kHz, longer than old note hold.
  if(dut.ramp!=256 || !active)$fatal(1,"persistent calibration ended");
  enable=0;for(k=0;k<270;k++)sample();
  if(active || left || right)$fatal(1,"fade did not reach exact silence");
  channels=1;amplitude=16423;frequency=1789570;enable=1;for(k=0;k<1000;k++)sample();
  if(right || !active)$fatal(1,"left isolation");
  enable=0;for(k=0;k<270;k++)sample();
  if(active || left || right)$fatal(1,"second stop");
  $fclose(file);$display("TB_PASS continuous sine, 5.33ms ramp, isolation, exact silence");$finish;
 end
endmodule
