`timescale 1ns/1ps
module tb_button_uart_hand;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,rx=1,cal=0,button_n=1;reg[7:0]f[0:37];reg[15:0]crc,seq=0;reg[31:0]tick=0;
 wire online,note_on;wire[255:0]status;wire[767:0]diag;wire scl,sda,rst_low;integer n,i,j,hits=0;
 bno_i2c_hand #(.BUTTON_TRIGGER(1),.CLK_HZ(1000000),.EXTERNAL_STREAM(1),.EXTERNAL_BAUD(100000)) d(
 .button_n(button_n),.clk(clk),.rst_n(rst_n),.enabled(1'b1),.force_reset(1'b0),.calibrate(cal),.express(1'b0),.mirror(1'b0),
 .layout_profile(2'd0),.scl_in(1'b1),.sda_in(1'b1),.int_n(rx),.snapshot_enable(1'b0),.stable_octave(2'd0),
 .online(online),.note_on(note_on),.status(status),.diagnostic(diag),.scl_low(scl),.sda_low(sda),.reset_low(rst_low));
 always @(posedge clk)begin
  if(note_on)begin hits=hits+1;if(status[25:22]!=3)$fatal(1,"wrong center hit zone");end
  if(scl||sda||rst_low)$fatal(1,"UART endpoint drove legacy I2C/reset pins");
 end
 task byte_out(input[7:0]b);integer k;begin
  @(negedge clk);rx=0;repeat(10)@(negedge clk);
  for(k=0;k<8;k=k+1)begin rx=b[k];repeat(10)@(negedge clk);end
  rx=1;repeat(10)@(negedge clk);
 end endtask
 task packet(input integer zz);integer a,b;begin
  seq=seq+1;tick=tick+50;
  for(a=0;a<38;a=a+1)f[a]=0;
  f[0]=8'ha5;f[1]=8'h5a;f[2]=1;f[3]=1;f[4]=30;f[6]=seq;f[7]=seq>>8;
  f[8]=tick;f[9]=tick>>8;f[10]=tick>>16;f[11]=tick>>24;f[12]=1;f[14]=7;f[15]=1;
  f[23]=8'h40;f[28]=zz;f[29]=zz>>>8;
  crc=16'hffff;for(a=2;a<36;a=a+1)begin crc=crc^{f[a],8'd0};for(b=0;b<8;b=b+1)crc=crc[15]?(crc<<1)^16'h1021:crc<<1;end
  f[36]=crc;f[37]=crc>>8;for(a=0;a<38;a=a+1)byte_out(f[a]);repeat(1200)@(negedge clk);
 end endtask
 initial begin
  repeat(10)@(negedge clk);rst_n=1;
  repeat(3)packet(0);if(!online||status[1])$fatal(1,"online before/without calibration");
  @(negedge clk);cal=1;@(negedge clk);cal=0;
  repeat(70)packet(0);if(!status[1]||!status[4])$fatal(1,"UART calibration/playable failed %h",status[31:0]);
  packet(-900);packet(-900);repeat(4)packet(0);if(hits!=0)$fatal(1,"motion triggered in button mode");
  button_n=0;repeat(5)packet(0);if(hits!=1)$fatal(1,"UART strike not delivered %d",hits);
  repeat(8)packet(0);if(hits!=1)$fatal(1,"held button repeated");
  repeat(100100)@(negedge clk);if(online||status[4])$fatal(1,"stale UART remained playable");
  repeat(4)packet(0);if(status[1]||hits!=1)$fatal(1,"reconnect reused old origin");
  $display("TB_PASS button through real UART endpoint/quaternion calibration, no motion strike, one press one event,hold,timeout and origin reset");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
