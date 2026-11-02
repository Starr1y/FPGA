`timescale 1ns/1ps
module tb_imu_uart_stream;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,rx=1,reset_stream=0;reg[7:0]f[0:37];reg[15:0]crc;
 wire online,qv,gv,lv,restarted;wire[31:0]stamp,errors,gaps;wire[7:0]seq;
 wire signed[15:0]lz;integer samples=0,resets=0,i,j;reg[31:0]previous_stamp;
 imu_uart_stream #(.CLK_HZ(1000000),.BAUD(100000)) d(.clk(clk),.rst_n(rst_n),.force_reset(reset_stream),.rx(rx),.quat_ready(1'b1),.linear_ready(1'b1),
 .online(online),.sensor_restarted(restarted),.quat_valid(qv),.gyro_valid(gv),.linear_valid(lv),.sequence_id(seq),.sample_timestamp(stamp),.errors(errors),.gaps(gaps),.lz(lz));
 always @(posedge clk)begin if(qv)begin samples=samples+1;if(!gv||!lv)$fatal(1,"incoherent sample strobes");end if(restarted)resets=resets+1;end
 integer clock_compares=0;
 always @(negedge clk)if(rst_n)begin
  if(d.timestamp_now!==(d.seen ? d.last_stamp+(d.ticks-d.last_arrival) : d.ticks))
   $fatal(1,"incremental stream clock differs from original extrapolation");
  clock_compares=clock_compares+1;
 end
 task byte_out(input[7:0]b);integer k;begin
  @(negedge clk);rx=0;repeat(10)@(negedge clk);
  for(k=0;k<8;k=k+1)begin rx=b[k];repeat(10)@(negedge clk);end
  rx=1;repeat(10)@(negedge clk);
 end endtask
 task packet(input integer sn,st,boot,flags,bad);integer a,b;begin
  for(a=0;a<38;a=a+1)f[a]=0;
  f[0]=8'ha5;f[1]=8'h5a;f[2]=1;f[3]=1;f[4]=30;f[6]=sn;f[7]=sn>>8;
  f[8]=st;f[9]=st>>8;f[10]=st>>16;f[11]=st>>24;f[12]=boot;f[13]=boot>>8;f[14]=flags;f[15]=1;
  f[23]=8'h40;f[28]=8'h00;f[29]=8'hfd; // qw=1.0, lz=-3.0m/s2
  crc=16'hffff;for(a=2;a<36;a=a+1)begin crc=crc^{f[a],8'd0};for(b=0;b<8;b=b+1)crc=crc[15]?(crc<<1)^16'h1021:crc<<1;end
  f[36]=crc[7:0]^(bad ? 1 : 0);f[37]=crc[15:8];
  for(a=0;a<38;a=a+1)byte_out(f[a]);repeat(30)@(negedge clk);
 end endtask
 initial begin
  repeat(10)@(negedge clk);rst_n=1;
  packet(1,1000,1,7,0);if(!online||samples!=0||resets!=1)$fatal(1,"first-session reset");
  packet(2,1050,1,7,0);if(samples!=1||seq!=2||lz!=-768||stamp!=1050)$fatal(1,"valid frame/acquisition timestamp");previous_stamp=stamp;
  packet(3,1100,1,7,1);if(samples!=1||errors!=1)$fatal(1,"bad CRC accepted");
  packet(4,1150,1,7,0);if(samples!=2||gaps!=1||stamp-previous_stamp!=100)$fatal(1,"gap/timestamp mapping");
  packet(4,1150,1,7,0);if(samples!=2||errors!=2)$fatal(1,"duplicate accepted");
  packet(5,1200,1,0,0);if(online)$fatal(1,"bad health remained online");
  packet(1,10,2,7,0);if(!online||samples!=2)$fatal(1,"reboot must reset before publish");
  packet(2,60,2,7,0);if(samples!=3)$fatal(1,"reboot recovery");
  repeat(100010)@(negedge clk);if(online)$fatal(1,"timeout didn't release");
  // A partial frame must time out and resynchronize on the next complete one.
  byte_out(8'ha5);byte_out(8'h5a);byte_out(1);repeat(10010)@(negedge clk);
  packet(3,110,2,7,0);if(!online||samples!=3)$fatal(1,"partial frame recovery");
  packet(4,160,2,7,0);if(samples!=4)$fatal(1,"post-timeout sample");
  // Cross-language fixture emitted by the exact C firmware packet encoder.
  $readmemh("validation/golden_frame.hex",f);
  for(i=0;i<38;i=i+1)byte_out(f[i]);repeat(30)@(negedge clk);
  if(!online||samples!=4)$fatal(1,"C encoder session frame");
  f[6]=f[6]+1;f[8]=f[8]+50;
  crc=16'hffff;for(i=2;i<36;i=i+1)begin crc=crc^{f[i],8'd0};for(j=0;j<8;j=j+1)crc=crc[15]?(crc<<1)^16'h1021:crc<<1;end
  f[36]=crc;f[37]=crc>>8;
  for(i=0;i<38;i=i+1)byte_out(f[i]);repeat(30)@(negedge clk);
  if(samples!=5||seq!=8'h35||lz!=-768)$fatal(1,"C encoder / RTL decoder mismatch");
  $display("TB_PASS stream clock equivalent each cycle; UART bits, CRC, coherent fields, gaps, duplicates, health, reboot, timeout, resync");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
