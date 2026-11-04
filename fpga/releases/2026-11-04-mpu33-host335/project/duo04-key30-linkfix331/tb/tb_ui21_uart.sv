`timescale 1ns/1ps
module tb_ui21_uart;
 reg[1:0]wrist_button_n=3;
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
  for(i=0;i<256;i++)ack[i]=-1;
  wirefile=$fopen("wire.hex","w");if(!wirefile)$fatal(1,"wire evidence open");
  repeat(25)@(negedge clk);
  if(!pa_en || dut.running)$fatal(1,"startup not muted");

  command(1,0,1,0,0);
  command(60,3,180,24'h000203,0); // saved left layout12
  command(60,3,181,24'h000305,0); // saved left octave code3
  command(60,3,182,24'h000107,0); // saved left chord
  command(61,1,190,7,0);repeat(5)@(negedge clk);
  if(!dut.ui_hand)$fatal(1,"UART virtual K2 not applied");
  command(61,1,191,6,0);repeat(5)@(negedge clk);
  if(dut.presets[5:3]!=1)$fatal(1,"UART K1 right timbre");
  command(62,2,192,16'h0001,0);repeat(5)@(negedge clk);
  if(dut.running || !dut.lesson_mouse || dut.operating_mode!=2 || dut.profiles!=0 || dut.chord)$fatal(1,"configure must mute and select teaching");
  command(63,1,193,1,0);
  data=0;data[31:0]=701;data[39:32]=1;data[71:64]=32;
  command(50,10,194,data,0);repeat(100)@(negedge clk);
  if(dut.lesson_wrong!=1 || dut.lesson_position!=0)$fatal(1,"mouse wrong hand not scored");
  data[31:0]=702;data[39:32]=0;
  command(50,10,195,data,0);repeat(100)@(negedge clk);
  if(dut.lesson_correct!=1 || dut.lesson_phase!=1 || dut.lesson_position!=0)$fatal(1,"correct hit did not hold target");
  data[31:0]=703;command(50,10,196,data,0);repeat(100)@(negedge clk);
  if(dut.lesson_correct!=1)$fatal(1,"repeat jumped lesson");
  command(63,1,197,2,0);repeat(5000)@(negedge clk);
  if(dut.running || dut.lesson_position!=0 || dut.lesson_phase!=1)$fatal(1,"pause lost feedback");
  command(63,1,198,3,0);
  // Unit bench checks exact 250/180ms. Only integration wait is shortened here.
  force dut.lesson.remaining=2;repeat(2)@(negedge clk);release dut.lesson.remaining;
  repeat(100100)@(negedge clk);
  if(dut.lesson_position!=1 || dut.lesson_phase!=0)$fatal(1,"resume feedback progression");
  command(17,3,230,24'h020000,0);
  command(61,1,231,7,0); // UI remains responsive while samples upload.
  wait_capture(1);
  if(dut.cap_id!=1 || dut.lesson_position!=1)$fatal(1,"capture/teaching interference");
  command(62,2,199,0,0);command(63,1,200,1,0);repeat(100)@(negedge clk);
  if(dut.running || dut.stop_reason!=5)$fatal(1,"offline target disconnect must pause");
  sensor_test_status=0;sensor_test_status[4]=1;sensor_test_status[21:18]=5;sensor_test_status[25:22]=3;sensor_test_status[159:128]=17;
  force dut.sensor_status=sensor_test_status;repeat(10)@(negedge clk);
  if(dut.status_bytes[103:96]!=8'h85 || dut.status_bytes[119:112]!=3 || dut.status_bytes[159:128]!=17)$fatal(1,"IMU state readback was replaced by mouse state");
  release dut.sensor_status;
  command(60,3,201,24'h000100,0);repeat(100)@(negedge clk);
  if(dut.operating_mode!=1 || dut.profiles[1:0]!=2 || dut.octave_left!=3 || !dut.chord || dut.running)$fatal(1,"lesson exit did not restore snapshot muted");
  command(61,1,202,11,0);command(61,1,203,255,2);command(62,1,204,0,2);command(63,1,205,6,2);
  command(1,0,206,0,0);command(1,0,207,0,0);command(1,0,208,0,0);
  $display("TB_PASS UI21 real UART controls/source/score/pause/restore/reconnect; feedback wait shortened only");
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
