`timescale 1ns/1ps
module tb_wrist_uart;
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
 integer k;reg[127:0]data;
 initial begin
  for(k=0;k<256;k++)ack[k]=-1;
  wirefile=$fopen("gesture_wire.hex","w");repeat(30)@(negedge clk);
  command(1,0,1,0,0);command(64,2,2,16'h0003,0);
  command(60,3,3,24'h000100,0); // PC mode
  data=0;data[0]=1;data[71:64]=8;command(48,9,4,data,0);
  for(k=0;k<12;k++)begin command(65,4,10+k,0,0);repeat(200000)@(negedge clk);end
  if(!dut.wrist_fresh[0] || dut.wrist_snapshot[1:0]!=0)$fatal(1,"fresh PC C4");
  data=0;data[31:0]=101;data[71:64]=64;command(50,10,30,data,0);
  for(k=0;k<4;k++)begin command(65,4,31+k,32'h00000100,0);repeat(200000)@(negedge clk);end
  if(!dut.wrist_pressed[0])$fatal(1,"virtual hold");
  for(k=0;k<10;k++)begin command(65,4,40+k,32'h01900100,0);repeat(200000)@(negedge clk);end
  if($signed(dut.wrist_bend[15:0])<950 || dut.gates[0]!=1)$fatal(1,"virtual pitch %d",$signed(dut.wrist_bend[15:0]));
  command(17,3,55,24'h020000,0);command(65,4,56,32'h01900100,0);wait_capture(1);
  command(65,4,57,32'h01900000,0);repeat(700000)@(negedge clk);
  if(dut.gates[0])$fatal(1,"virtual release gate");
  command(64,2,58,0,2); // cannot edit live
  command(51,0,59,0,0);command(64,2,60,0,0);
  command(60,3,61,0,0);command(65,4,62,0,2); // cannot inject offline
  command(1,0,63,0,0);command(1,0,64,0,0);
  $display("TB_PASS GEST24 real UART configure, live-edit refusal, source lock, bend,512capture,release,reconnect");$fclose(wirefile);$finish;
 end
 initial begin #3000000000.0;$fatal(1,"timeout");end
 endmodule
