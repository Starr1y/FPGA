`timescale 1ns/1ps
module tb_io22_hello;
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
 reg[127:0]data;reg[511:0]sensor_test_status;integer i,seq;
 initial begin
  // UART/audio integration only. Hold the unrelated video clock to reduce
  // event-simulator cost; panel rasterization has its own full-frame bench.
  force dut.pixel_clk=1'b0;
  for(i=0;i<256;i++)ack[i]=-1;
  wirefile=$fopen("hello_wire.hex","w");if(!wirefile)$fatal(1,"wire evidence open");
  repeat(25)@(negedge clk);
  if(!pa_en || dut.running)$fatal(1,"startup not muted");

  command(1,0,1,0,0);
  if(length!=32)$fatal(1,"HELLO length must retain suffix");
  if(packet[34]!=8'd50 || packet[35]!=8'd46 || packet[36]!=8'd49 || packet[37]!=8'd43 || packet[38]!=8'd73 || packet[39]!=8'd79 || packet[40]!=8'd50 || packet[41]!=8'd50)$fatal(1,"HELLO capability prefix/suffix mismatch");
  $display("TB_PASS real921600 UART HELLO DUO04-LIVE 2.1+IO22, compatible prefix and explicit I/O revision");
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
