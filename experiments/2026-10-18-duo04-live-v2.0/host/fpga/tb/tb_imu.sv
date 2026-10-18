`timescale 1ns/1ps
module tb_imu;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0;reg [31:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
 reg mode_valid=0;reg [1:0] mode_in=0;reg tx_request=0;reg [6:0] tx_length=0;reg [511:0] tx_payload=0;
 wire tx_busy;reg imu_data=1,imu_int_n=1;
 wire imu_clk_tx,imu_cs_n,imu_mosi,imu_rst_n,imu_wake,packet_ready;
 reg packet_take=0;wire [9:0] packet_length;reg [9:0] read_addr=0;wire [7:0] read_data;wire [31:0] stamp_start,stamp_end,stamp_parsed,drops;wire [1:0] mode;
 imu_transport dut(.*);
 reg [7:0] expected[0:63];integer i,k;reg [7:0] got;
 task setmode(input [1:0] m);
  begin @(negedge clk);mode_in=m;mode_valid=1;@(negedge clk);mode_valid=0;wait(!imu_rst_n);wait(imu_rst_n);#200;end
 endtask
 task byte_uart(input [7:0] b,input realtime bit_ns);
  integer k;begin imu_data=0;#(bit_ns);for(k=0;k<8;k=k+1)begin imu_data=b[k];#(bit_ns);end imu_data=1;#(bit_ns);end
 endtask
 task check_packet(input integer n);
  integer k;begin
   wait(packet_ready);#100;
   if(packet_length!==n)$fatal(1,"length expected %0d actual %0d",n,packet_length);
   for(k=0;k<n;k=k+1)begin read_addr=k;#40;if(read_data!==expected[k])$fatal(1,"byte %0d got %02x expected %02x",k,read_data,expected[k]);end
   if(stamp_end<=stamp_start)$fatal(1,"timestamps");
   @(negedge clk);packet_take=1;@(negedge clk);packet_take=0;
  end
 endtask
 initial begin
  #100;rst_n=1;wait(imu_rst_n);#100;
  expected[0]=8'haa;expected[1]=8'haa;for(i=2;i<19;i=i+1)expected[i]=i;
  for(i=0;i<19;i=i+1)byte_uart(expected[i],8680.555);
  check_packet(19);$display("RVC receive PASS");
  setmode(1);
  expected[0]=8'h7e;expected[1]=1;expected[2]=5;expected[3]=0;expected[4]=1;expected[5]=0;expected[6]=1;expected[7]=8'h7e;
  imu_int_n=0;#200;
  for(i=0;i<8;i=i+1)byte_uart(expected[i],333.333);
  imu_int_n=1;check_packet(8);$display("SHTP UART receive PASS");
  setmode(2);
  expected[0]=8;expected[1]=0;expected[2]=2;expected[3]=7;expected[4]=8'hfc;expected[5]=5;expected[6]=8'hab;expected[7]=8'hcd;
  imu_int_n=0;wait(!imu_cs_n);imu_int_n=1;
  for(i=0;i<8;i=i+1)begin
   for(k=7;k>=0;k=k-1)begin @(negedge imu_clk_tx);imu_data=expected[i][k];@(posedge imu_clk_tx);end
  end
  wait(imu_cs_n);check_packet(8);$display("SPI receive PASS");
  @(negedge clk);tx_payload=512'h7856341200020008;tx_length=8;tx_request=1;
  @(negedge clk);tx_request=0;wait(!imu_wake);imu_int_n=0;wait(!imu_cs_n);imu_int_n=1;
  for(i=0;i<8;i=i+1)begin
   got=0;
   for(k=7;k>=0;k=k-1)begin @(negedge imu_clk_tx);imu_data=0;@(posedge imu_clk_tx);got[k]=imu_mosi;end
   if(got!==tx_payload[i*8+:8])$fatal(1,"SPI TX mismatch");
  end
  wait(imu_cs_n);wait(!tx_busy);
  if(drops!=0)$fatal(1,"Unexpected drops %0d",drops);
  $display("TB_PASS three IMU transports and SPI TX");$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
