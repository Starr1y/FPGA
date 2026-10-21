`timescale 1ns/1ps
module tb_mouse_uart;
 reg clk=0;always #10 clk=~clk;
 reg reset_key=0,key0_n=1,key1_n=1,key2_n=1,pc_rx=1;
 tri[1:0]imu_scl,imu_sda,imu_rst_n;reg[1:0]imu_int_n=3;
 wire hp_bck,hp_ws,hp_din,pa_en,pc_tx,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 // Packet gaps are shortened; sample rate, audio size, UART and FX RAM are production values.
 top_duo02_mouse #(.BOOT_CYCLES(16),.KEY_DEBOUNCE(8),.CAPTURE_GAP_CYCLES(5000)) dut(.*);
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
  if(imu_scl!==2'bzz || imu_sda!==2'bzz || imu_rst_n!==2'bzz)$fatal(1,"IMU driven in mouse test");
  command(1,0,1,0,0);
  data=0;data[71:0]={8'd8,8'd128,8'd0,8'd0,8'd0,8'd0,8'd0,8'd0,8'd1};
  command(48,9,2,data,0);
  command(49,3,3,24'h000100,0);
  if(!dut.selected_valid[0] || dut.selected_zone[3:0]!=0)$fatal(1,"preselection mismatch");
  data=0;data[31:0]=101;data[71:64]=32;data[79:72]=1;
  command(50,10,4,data,0);
  wait(dut.cap_ready);
  // A second click during upload must sound, but cannot overwrite the first capture.
  data[31:0]=102;data[47:40]=2;
  command(50,10,5,data,0);
  // Change selection while the first upload is busy: captured IDs must remain frozen.
  command(54,5,88,40'h1f100003,0);
  if(dut.cap_monitor_count!=2 || dut.cap_monitor_ids!=32'hffff1000)$fatal(1,"selection changed in-flight capture");
  if(dut.hits0!=2 || dut.cap_event!=101 || dut.skipped_captures!=1)$fatal(1,"busy capture suppressed/corrupted a strike");
  wait_capture(1);
  command(51,0,6,0,0);repeat(500000)@(negedge clk);
  if(!pa_en || dut.active!=0)$fatal(1,"stop left audio active");
  data=0;data[71:0]={8'd8,8'd128,8'd0,8'd0,8'd0,8'd1,8'd0,8'd0,8'd1};
  command(48,9,7,data,0);
  data=0;data[31:0]=201;data[39:32]=1;data[71:64]=32;data[79:72]=1;
  command(50,10,8,data,0);wait_capture(2);
  // Plain 2048 capture remains independent from strike-tagged captures.
  command(17,3,9,24'h080000,0);wait_capture(3);
  command(51,0,10,0,0);repeat(20000)@(negedge clk);
  data=0;data[71:0]={8'd8,8'd128,8'd3,8'd1,8'd0,8'd0,8'd0,8'd0,8'd1};
  command(48,9,11,data,0); // major triad on the left, reverb requested
  data=0;data[31:0]=301;data[47:40]=1;data[71:64]=48;
  command(50,10,12,data,0);repeat(10000)@(negedge clk);
  if(dut.notes[6:0]!=62 || dut.notes[13:7]!=65 || dut.notes[20:14]!=69)$fatal(1,"diatonic chord mapping");
  command(51,0,13,0,0);
  data=0;data[71:0]={8'd8,8'd128,8'd0,8'd0,8'd2,8'd2,8'd2,8'd2,8'd1};command(48,9,14,data,0);
  // Fill both 16-Voice pools through real UART; repeated notes still allocate separately.
  for(i=0;i<32;i++)begin
   data=0;data[31:0]=400+i;data[39:32]=i>=16;data[47:40]=i%12;data[55:48]=2;data[71:64]=32;
   command(50,10,15+i,data,0);
  end
  repeat(20000)@(negedge clk);
  if(dut.active!==32'hffffffff || dut.underflows || dut.fx_drops)$fatal(1,"32Voice starvation/underflow");
  command(50,10,48,0,2); // Invalid velocity rejected.
  command(51,0,50,0,0);
  // Extended settings retain all nine gain bits and independent hand durations.
  data=0;data[7:0]=1;data[31:24]=2;data[39:32]=2;data[79:64]=128;
  data[95:80]=100;data[111:96]=300;data[119:112]=4;
  command(48,15,51,data,0);
  if(dut.test_gain!=128 || dut.hold_ticks_left!=5000000 || dut.hold_ticks_right!=15000000 || dut.release_ids!=4)$fatal(1,"extended configuration truncation");
  data=0;data[31:0]=601;data[71:64]=96;command(50,10,52,data,0);
  data[31:0]=602;data[39:32]=1;command(50,10,53,data,0);
  repeat(7500000)@(negedge clk);
  if(dut.gates[15:0]!=0 || dut.gates[31:16]==0)$fatal(1,"independent hold expiration");
  repeat(10000000)@(negedge clk);
  if(dut.gates!=0)$fatal(1,"right hold did not expire");
  data=0;data[7:0]=1;data[31:24]=2;data[39:32]=2;data[79:64]=256;
  data[95:80]=100;data[111:96]=100;data[119:112]=0;
  command(48,15,54,data,0);
  if(dut.test_gain!=256)$fatal(1,"256 gain truncated");
  // V1.2 wire path: full 3-bit piano ID, hold flags and both coefficients.
  data=0;data[7:0]=1;data[31:24]=4;data[39:32]=4;data[79:64]=32;
  data[95:80]=1500;data[111:96]=1500;data[119:112]=5;data[127:120]=3;
  // command() below now supports the full 20-byte payload.
  command_quality(55);
  if(dut.presets!=6'b100100 || dut.piano_hold!=3 || dut.piano_coefficients!={16'd134,16'd134})$fatal(1,"piano wire settings");
  for(i=0;i<32;i++)begin
   data=0;data[31:0]=800+i;data[39:32]=i>=16;data[47:40]=i%7;data[71:64]=96;
   command(50,10,56+i,data,0);
  end
  repeat(20000)@(negedge clk);
  if(dut.active!==32'hffffffff || dut.underflows || dut.fx_drops)$fatal(1,"32 piano starvation/limiter drop");
  key2_n=0;repeat(20)@(negedge clk);key2_n=1;repeat(500000)@(negedge clk);
  if(dut.running || !pa_en || dut.stop_reason!=3)$fatal(1,"KEY2 emergency stop");
  data=0;data[71:0]={8'd8,8'd128,8'd0,8'd0,8'd0,8'd0,8'd0,8'd0,8'd1};command(48,9,49,data,0);
  @(negedge clk);dut.link_age=99999999;repeat(5)@(negedge clk);
  if(dut.running || dut.stop_reason!=2)$fatal(1,"watchdog boundary");
  repeat(1000000)@(negedge clk);
  if(dut.rx_errors || words<1000 || different<100 || !pa_en)$fatal(1,"serial/reset/coverage");
  // Direct calibration is exclusive, persistent, captured as calibration with no voice IDs.
  data=0;data[7:0]=1;data[39:8]=89478485;data[55:40]=1036;data[63:56]=3;
  command(55,8,90,data,0);repeat(500000)@(negedge clk);
  if(!dut.sine_enable || dut.running || pa_en)$fatal(1,"calibration not active");
  command(17,3,91,24'h020000,0);wait_capture(4);
  if(dut.cap_monitor_count!=0 || !dut.cap_sine_mode)$fatal(1,"calibration misidentified as voices");
  command(56,0,92,0,0);repeat(300000)@(negedge clk);
  if(dut.sine_active || !pa_en)$fatal(1,"calibration stop failed");
  command(17,3,93,24'h020000,0);wait_capture(5);
  if(dut.cap_monitor_count!=3 || dut.cap_monitor_ids[23:0]!=24'h1f1000)$fatal(1,"next capture routing");
  data=0;data[7:0]=1;data[39:8]=89478485;data[55:40]=1036;data[63:56]=1;
  command(55,8,94,data,0);key2_n=0;repeat(20)@(negedge clk);key2_n=1;repeat(300000)@(negedge clk);
  if(dut.sine_active || !pa_en || dut.stop_reason!=3)$fatal(1,"calibration KEY2 protection");
  command(55,8,95,data,0);@(negedge clk);dut.link_age=99999999;repeat(300000)@(negedge clk);
  if(dut.sine_active || !pa_en || dut.stop_reason!=2)$fatal(1,"calibration watchdog");
  $fclose(wirefile);
  $display("TB_PASS UART->32Voice/stereo/FX/PT8211, two onset captures, busy capture, 2048, chord, KEY2/watchdog, %d words",words);$finish;
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
