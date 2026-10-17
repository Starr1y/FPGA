`timescale 1ns/1ps
module tb_audio;
 reg piano_config_valid=0;reg [31:0] piano_config_data=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0,config_valid=0;reg [135:0] config_data=0;
 wire [79:0] samples;wire sample_valid;wire [31:0] clips;
 audio_core dut(.*);
 wire bck,ws,dout,tick;
 reg [15:0] pcm=0;
 i2s_output serial(clk,rst_n,pcm,bck,ws,dout,tick);
 integer channels=0,bits=0;reg last_ws=1;reg [15:0] assembled=0,expected=0;reg enabled=0;
 // PT8211 model: exactly 16 rising BCK edges per WS level, MSB first.
 // Unlike the old test, the LSB must still be sampled under the old WS.
 always @(posedge bck)if(rst_n)begin
  if(!enabled || ws!=last_ws)begin
   if(enabled && bits!=16)$fatal(1,"WS changed before 16 bits: %0d",bits);
   bits=0;assembled=0;enabled=1;
   if(!ws)expected=pcm;
   last_ws=ws;
  end
  assembled={assembled[14:0],dout};bits=bits+1;
  if(bits==16)begin
   if(assembled!==expected)$fatal(1,"PT8211 word expected %04x got %04x",expected,assembled);
   channels=channels+1;
  end
  if(bits>16)$fatal(1,"Too many bits per WS");
 end
 task step;
  begin @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;wait(sample_valid);@(negedge clk);end
 endtask
 task configure(input integer i,input integer gate);
  begin
   @(negedge clk);config_data={8'hff,16'hffff,16'hffff,16'hffff,16'hffff,8'(gate),8'd2,8'd255,32'd0,8'(i)};
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
  // Full envelope, square +32767, fine gain 131/65536 ~= 0.002.
  configure(0,1);
  @(negedge clk);config_data[135:128]=0;config_data[47:40]=131;config_valid=1;
  @(negedge clk);config_valid=0;repeat(5)step();
  if(samples[15:0]!=65)$fatal(1,"fine gain 0.002 expected65 got%0d",samples[15:0]);
  @(negedge clk);config_data[47:40]=0;config_valid=1;
  @(negedge clk);config_valid=0;repeat(3)step();
  if(samples!==80'd0)$fatal(1,"zero gain not silent");
  #100000;pcm=16'h0001;#100000;pcm=16'hffff;
  #100000;pcm=16'h005a;#100000;pcm=16'hffa6;
  #100000;pcm=16'h7fff;#100000;pcm=16'h8000;
  #100000;pcm=0;#100000;
  if(channels<10)$fatal(1,"I2S frames missing");
  $display("TB_PASS fine/zero gain, saturation, PT8211 signed words and WS boundaries");$finish;
 end
 initial begin #5000000;$fatal(1,"watchdog");end
endmodule
