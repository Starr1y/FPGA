`timescale 1ns/1ps
module tb_duo04_uart;
 wire i2s_bck,i2s_ws,i2s_dout;
 reg clk=0;always #10 clk=~clk;
 reg encoder_a=1,encoder_b=1,encoder_button_n=1;
 reg reset_key=0,key0_n=1,key1_n=1,key2_n=1,pc_rx=1;
 tri[1:0]imu_scl,imu_sda,imu_rst_n;reg[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,pc_tx,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 // Packet gaps are shortened; sample rate, audio size, UART and FX RAM are production values.
 top_duo04 #(.BOOT_CYCLES(16),.KEY_DEBOUNCE(8),.CAPTURE_GAP_CYCLES(5000)) dut(.*);
 wire[7:0]byte_in;wire byte_valid;
 uart_rx listener(.clk(clk),.rst_n(dut.rst_n),.rx(pc_tx),.baud(32'd921600),.data(byte_in),.valid(byte_valid),.start(),.error());
 integer wirefile,parser=0,index=0,length=0,typ=0,completed_captures=0,offset,total,monitor_n=2;
 integer ack[0:255];reg[7:0]packet[0:4095];
 always @(posedge clk)if(byte_valid)begin
  $fwrite(wirefile,"%02x ",byte_in);
  case(parser)
   0:if(byte_in==8'ha5)parser=1;
   1:if(byte_in==8'h5a)begin parser=2;index=0;end else parser=0;
   2:begin
    packet[index]=byte_in;
    if(index==1)typ=byte_in;
    if(index==2)length=byte_in;
    if(index==3)length=length+256*byte_in;
    if(index==length+11)begin
     if(typ==128 || typ==129 || typ==134)ack[packet[10]+256*packet[11]]=typ==128 ? 0 : packet[12];
     if(typ==139)monitor_n=packet[12];
     if(typ==138 || typ==130 && monitor_n==0)begin
      offset=packet[12]+256*packet[13];total=packet[14]+256*packet[15];
      if(offset+32==total)completed_captures++;
     end
     parser=0;
    end else index++;
   end
  endcase
 end
 function[15:0]crcbyte(input[15:0]crc,input[7:0]b);
  reg[15:0]v;integer n;begin v=crc^{b,8'b0};for(n=0;n<8;n++)v=v[15]?(v<<1)^16'h1021:v<<1;crcbyte=v;end
 endfunction
 task sendbyte(input[7:0]b);
  integer i;begin @(negedge clk);pc_rx=0;repeat(54)@(negedge clk);
   for(i=0;i<8;i++)begin pc_rx=b[i];repeat(54)@(negedge clk);end
   pc_rx=1;repeat(58)@(negedge clk);
  end
 endtask
 task command(input integer kind,n,seq,input[127:0]data,input integer expected);
  reg[15:0]crc;reg[7:0]b;integer i,timeout;
  begin
   sendbyte(8'ha5);sendbyte(8'h5a);crc=16'hffff;
   for(i=0;i<10+n;i++)begin
    case(i)0:b=1;1:b=kind;2:b=n;3:b=0;4:b=seq;5:b=0;6,7,8,9:b=0;default:b=data[(i-10)*8+:8];endcase
    sendbyte(b);crc=crcbyte(crc,b);
   end
   sendbyte(crc[7:0]);sendbyte(crc[15:8]);timeout=0;
   while(ack[seq]<0)begin @(negedge clk);timeout++;if(timeout>1000000)$fatal(1,"ACK timeout seq=%d",seq);end
   if(ack[seq]!=expected)$fatal(1,"ACK seq %d expected %d got %d",seq,expected,ack[seq]);
  end
 endtask
 task wait_capture(input integer n);
  integer timeout;begin timeout=0;while(completed_captures<n)begin @(negedge clk);timeout++;if(timeout>30000000)$fatal(1,"capture timeout");end end
 endtask
 reg old_ws=0;reg[15:0]word=0,held_l=0,held_r=0;integer bits=0,words=0,different=0;bit decoding=0;
 always @(negedge hp_bck)begin #1;if(dut.dac.slot==1 && dut.rst_n)begin held_l=dut.dac.held_left;held_r=dut.dac.held_right;if(held_l!=held_r)different++;end end
 always @(posedge hp_bck)if(dut.rst_n)begin
  if(hp_ws!=old_ws)begin if(decoding && bits!=16)$fatal(1,"PT8211 bit length");old_ws=hp_ws;bits=0;word=0;decoding=1;end
  if(decoding)begin word={word[14:0],hp_din};bits++;if(bits==16)begin
   if(word!==(hp_ws ? held_l : held_r))$fatal(1,"serial PCM mismatch");words++;
  end end
 end
 reg[127:0]data;integer i,seq;
 initial begin
  for(i=0;i<256;i++)ack[i]=-1;
  wirefile=$fopen("wire.hex","w");if(!wirefile)$fatal(1,"wire evidence open");
  repeat(25)@(negedge clk);
  if(!pa_en || dut.running)$fatal(1,"startup not muted");

  command(1,0,1,0,0);
  command(60,3,240,24'h000100,0);
  repeat(10)@(negedge clk);
  if(dut.operating_mode!=1)$fatal(1,"mode not accepted");
  command(54,5,239,40'h1f100f0004,0);
  command(60,3,238,24'h00640b,0);repeat(10)@(negedge clk);
  if(dut.hold_samples_left!=4800)$fatal(1,"milliseconds to sample count");
  data=0;data[71:0]={8'd8,8'd128,8'd0,8'd0,8'd0,8'd0,8'd0,8'd0,8'd1};
  command(48,9,2,data,0);
  command(49,3,3,24'h000100,0);
  if(!dut.selected_valid[0] || dut.selected_zone[3:0]!=0)$fatal(1,"preselection mismatch");
  data=0;data[31:0]=101;data[71:64]=32;data[79:72]=1;
  command(50,10,4,data,0);
  wait(dut.cap_ready);
  wait_capture(1);
  command(51,0,5,0,0);
  repeat(100000)@(negedge clk);
  if(dut.running)$fatal(1,"stop ignored");
  $display("TB_PASS real UART handshake/mode/config/strike/512 capture/stop");
  $fclose(wirefile);$finish;
 end
 initial begin #3000000000.0;$fatal(1,"simulation watchdog");end
 task command_quality(input integer seqno);
  reg[159:0]payload;reg[15:0]crc;reg[7:0]b;integer j,timeout;
  begin
   payload={16'd134,16'd134,data};sendbyte(8'ha5);sendbyte(8'h5a);crc=16'hffff;
   for(j=0;j<30;j++)begin
    case(j)0:b=1;1:b=48;2:b=20;3:b=0;4:b=seqno;5,6,7,8,9:b=0;default:b=payload[(j-10)*8+:8];endcase
    sendbyte(b);crc=crcbyte(crc,b);
   end
   sendbyte(crc[7:0]);sendbyte(crc[15:8]);timeout=0;
   while(ack[seqno]<0)begin @(negedge clk);timeout++;if(timeout>1000000)$fatal(1,"piano ACK timeout");end
   if(ack[seqno]!=0)$fatal(1,"piano command rejected");
  end
 endtask
endmodule
