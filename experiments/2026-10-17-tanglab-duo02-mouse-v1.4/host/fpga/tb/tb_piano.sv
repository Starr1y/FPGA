`timescale 1ns/1ps
module tb_piano;
 reg piano_config_valid=0;reg [31:0] piano_config_data=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0,config_valid=0;reg [135:0] config_data=0;
 wire [79:0] samples;wire sample_valid;wire [31:0] clips;
 audio_core dut(.*);
 reg check_high=0;
 always @(negedge clk)if(check_high && dut.voice==0 && dut.state==9 && dut.piano_partial!==0)$fatal(1,"above Nyquist partial retained");
 integer n,i,fd,cycles,total;reg signed [15:0] first[0:255];
 task step;
  begin
   @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
   while(!sample_valid)begin @(negedge clk);cycles=cycles+1;if(cycles>70)$fatal(1,"sample deadline");end
   if(^samples===1'bx)$fatal(1,"unknown sample");
   total=0;for(i=0;i<4;i=i+1)total=total+$signed(samples[i*16+:16]);
   if(total!=$signed(samples[79:64]))$fatal(1,"mix mismatch");
  end
 endtask
 task configure(input integer channel,input integer gate,input [31:0] freq);
  begin
   @(negedge clk);
   config_data={8'h40,16'hffff,16'hffff,16'hffff,16'hffff,8'(gate),8'd4,8'h00,freq,8'(channel)};
   config_valid=1;@(negedge clk);config_valid=0;
  end
 endtask
 initial begin
  fd=$fopen("piano.csv","w");if(!fd)$fatal(1,"no output file");
  #100;rst_n=1;step();if(samples!==0)$fatal(1,"startup not silent");
  for(n=0;n<4;n=n+1)configure(n,1,32'd33554432*(n+1));
  for(n=0;n<96000;n=n+1)begin
   step();if(n<256)first[n]=$signed(samples[15:0]);
   $fwrite(fd,"%0d,%0d,%0d,%0d,%0d\n",$signed(samples[15:0]),$signed(samples[31:16]),$signed(samples[47:32]),$signed(samples[63:48]),$signed(samples[79:64]));
  end
  $fclose(fd);
  for(n=0;n<4;n=n+1)configure(n,0,32'd33554432*(n+1));
  repeat(3)step();if(samples!==0)$fatal(1,"release not silent");
  configure(0,1,32'd33554432);
  for(n=0;n<256;n=n+1)begin step();if($signed(samples[15:0])!==first[n])$fatal(1,"retrigger mismatch");end
  configure(0,0,32'd1789569707);repeat(3)step();configure(0,1,32'd1789569707);check_high=1;repeat(128)step();
  $display("TB_PASS piano four voices, mix, sample deadline, release, retrigger, Nyquist guard");$finish;
 end
 initial begin #200000000;$fatal(1,"watchdog");end
endmodule
