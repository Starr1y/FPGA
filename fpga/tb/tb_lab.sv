`timescale 1ns/1ps
module tb_lab;
 reg clk=0;always #10 clk=~clk;
 reg pc_rx=1,reset_key=0,imu_data=1,imu_int_n=1;
 wire pc_tx,imu_clk_tx,imu_cs_n,imu_mosi,imu_rst_n,imu_wake,hp_bck,hp_ws,hp_din,pa_en,event_mark,audio_mark;
 top dut(.*);
 integer file_out,count=0;reg [7:0] bytes[0:127];reg [15:0] crc;integer j;
 wire [7:0] rx;wire valid,start,error;
 uart_rx receiver(clk,dut.rst_n,pc_tx,32'd921600,rx,valid,start,error);
 always @(posedge clk)if(valid)begin $fwrite(file_out,"%02x\n",rx);count=count+1;end
 function [15:0] crcnext(input [15:0] c,input [7:0] d);
  reg [15:0] t;integer k;begin t=c^{d,8'b0};for(k=0;k<8;k=k+1)t=t[15]?(t<<1)^16'h1021:t<<1;crcnext=t;end
 endfunction
 task uart_byte(input [7:0] b);
  integer k;begin pc_rx=0;#1085;for(k=0;k<8;k=k+1)begin pc_rx=b[k];#1085;end pc_rx=1;#1085;end
 endtask
 task command(input [7:0] kind,input integer n,input integer seq);
  integer k;begin
   bytes[0]=1;bytes[1]=kind;bytes[2]=n;bytes[3]=0;bytes[4]=seq;bytes[5]=0;
   for(k=6;k<10;k=k+1)bytes[k]=0;
   crc=16'hffff;uart_byte(8'ha5);uart_byte(8'h5a);
   for(k=0;k<10+n;k=k+1)begin crc=crcnext(crc,bytes[k]);uart_byte(bytes[k]);end
   uart_byte(crc[7:0]);uart_byte(crc[15:8]);#1000000;
  end
 endtask
 initial begin
  file_out=$fopen("wire.hex","w");
  wait(dut.rst_n);#10000;
  command(1,0,0);
  for(j=0;j<4;j=j+1)begin
   bytes[10]=j;bytes[11]=0;bytes[12]=0;bytes[13]=0;bytes[14]=2*(j+1);
   bytes[15]=46;bytes[16]=0;bytes[17]=1;
   bytes[18]=255;bytes[19]=255;bytes[20]=255;bytes[21]=255;bytes[22]=255;bytes[23]=255;bytes[24]=32;bytes[25]=0;
   command(16,16,j+1);
  end
  #2000000;bytes[10]=0;command(17,1,5);
  wait(dut.cap_ready);wait(!dut.cap_ready);#1000000;
  if(count<20000)$fatal(1,"Missing capture data %0d",count);
  if(dut.clips!=0)$fatal(1,"Unexpected clipping");
  $fclose(file_out);$display("TB_PASS top capture bytes=%0d",count);$finish;
 end
 initial begin #600000000;$fatal(1,"watchdog");end
endmodule
