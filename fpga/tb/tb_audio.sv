`timescale 1ns/1ps
module tb_audio;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0,config_valid=0;reg [127:0] config_data=0;
 wire [79:0] samples;wire sample_valid;wire [31:0] clips;
 audio_core dut(.*);
 wire bck,ws,dout,tick;
 i2s_output serial(clk,rst_n,16'ha55a,bck,ws,dout,tick);
 integer channels=0,bits=0;reg last_ws=1;reg [15:0] assembled=0;reg enabled=0;
 always @(posedge bck)if(rst_n)begin
  if(ws!=last_ws)begin
   if(enabled && bits==15)begin
    assembled={assembled[14:0],dout};
    if(channels>1 && assembled!==16'ha55a)$fatal(1,"I2S shift %04x",assembled);
    channels=channels+1;
   end
   bits=0;last_ws=ws;enabled=1;
  end
  else if(enabled)begin
   assembled={assembled[14:0],dout};bits=bits+1;
   if(bits==16)begin if(channels>1 && assembled!==16'ha55a)$fatal(1,"I2S shift %04x",assembled);channels=channels+1;bits=0;end
  end
 end
 task step;
  begin @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;wait(sample_valid);@(negedge clk);end
 endtask
 task configure(input integer i,input integer gate);
  begin
   @(negedge clk);config_data={16'hffff,16'hffff,16'hffff,16'hffff,8'(gate),8'd2,8'd255,32'd0,8'(i)};
   config_valid=1;@(negedge clk);config_valid=0;
  end
 endtask
 integer i;
 initial begin
  #100;rst_n=1;
  for(i=0;i<4;i=i+1)configure(i,1);
  repeat(5)step();
  if(samples[79:64]!==16'h7fff || clips==0)$fatal(1,"positive saturation");
  for(i=0;i<4;i=i+1)configure(i,0);
  repeat(3)step();
  if(samples!==80'd0)$fatal(1,"release did not silence");
  #1000000;
  if(channels<10)$fatal(1,"I2S frames missing");
  $display("TB_PASS ADSR silence/saturation and I2S sample bits");$finish;
 end
 initial begin #5000000;$fatal(1,"watchdog");end
endmodule
