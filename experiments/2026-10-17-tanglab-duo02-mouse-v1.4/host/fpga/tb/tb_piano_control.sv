`timescale 1ns/1ps
module tb_piano_control;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0,config_valid=0,piano_config_valid=0;
 reg [135:0] config_data=0;reg [31:0] piano_config_data=0;
 wire [79:0] samples;wire sample_valid;wire [31:0] clips;
 audio_core dut(.*);
 integer n,k,cycles;integer nonzero=0;reg [23:0] start_body;
 task step;
 begin
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
  while(!sample_valid)begin @(negedge clk);cycles=cycles+1;if(cycles>70)$fatal(1,"sample deadline");end
  if(^samples===1'bx)$fatal(1,"unknown sample");
 end
 endtask
 task voice_config(input integer ch,input integer w,input integer g);
 begin
  @(negedge clk);config_data={8'h04,16'hffff,16'hffff,16'hffff,16'hffff,8'(g),8'(w),8'h00,32'd33554432,8'(ch)};
  config_valid=1;@(negedge clk);config_valid=0;
 end
 endtask
 task piano(input integer ch,input integer hold_flag,input integer coeff);
 begin
  @(negedge clk);piano_config_data={16'(coeff),8'(hold_flag),8'(ch)};
  piano_config_valid=1;@(negedge clk);piano_config_valid=0;
 end
 endtask
 initial begin
  #100;rst_n=1;step();if(samples!==0)$fatal(1,"startup not silent");
  // Four settings stay independent; channel 0 sustains for eleven audio seconds.
  for(k=0;k<4;k=k+1)begin piano(k,k==0, k==1?4024:134);voice_config(k,4,1);end
  for(n=0;n<528000;n=n+1)begin step();if(n>480000 && samples[15:0]!=0)nonzero=nonzero+1;end
  if(nonzero<40000 || dut.piano_body[0]!==24'hffffff)$fatal(1,"hold lost energy");
  if(dut.piano_body[1]>5000 || dut.piano_hold[1]!==0 || dut.piano_coefficient[1]!=4024)$fatal(1,"per voice configuration");
  piano(0,0,4024);start_body=dut.piano_body[0];
  repeat(9600)step();
  if(dut.piano_body[0]<start_body/100*9 || dut.piano_body[0]>start_body/100*11)$fatal(1,"T10 0.2 seconds incorrect %d",dut.piano_body[0]);
  // Editing a coefficient does not strike again.
  start_body=dut.piano_body[0];piano(0,0,134);step();
  if(dut.piano_body[0]>start_body)$fatal(1,"parameter edit retriggered");
  // Gate stays on during wave switch: exactly one fresh attack.
  voice_config(0,0,1);step();voice_config(0,4,1);step();
  if(dut.piano_body[0]<24'hff0000)$fatal(1,"wave switch did not strike");
  repeat(288000)step();
  if(dut.piano_body[0]<1620000 || dut.piano_body[0]>1740000)$fatal(1,"T10 six seconds incorrect %d",dut.piano_body[0]);
  // Slowest coefficient and small energy expose per-sample truncation bias.
  piano(0,0,27);dut.piano_body[0]=24'd100000;dut.piano_fraction[0]=0;
  repeat(1440000)step();
  if(dut.piano_body[0]<9700 || dut.piano_body[0]>10300)$fatal(1,"T10 thirty seconds drift %d",dut.piano_body[0]);
  for(k=0;k<4;k=k+1)voice_config(k,4,0);
  repeat(3)step();if(samples!==0)$fatal(1,"release not silent");
  $display("TB_PASS hold eleven seconds, independent settings, T10 0.2/6/30 seconds, edit no strike, wave switch attack, release");$finish;
 end
 initial begin #(64'd4000000000);$fatal(1,"watchdog");end
endmodule
