`timescale 1ns/1ps
// Real 50MHz/48kHz board top with two pin-level 100Hz SHTP peers.
// Only startup waits and note hold are overridden; controls have their own release/bounce bench.
module tb_duo_board;
 reg clk=0;always #10 clk=~clk;
 reg reset_key=0;reg key0_n=1,key1_n=1,key2_n=1;
 tri1[1:0]imu_scl,imu_sda,imu_rst_n;wire[1:0]imu_int_n,configured;
 wire hp_bck,hp_ws,hp_din,pa_en,tmds_clk_p_0,tmds_clk_n_0;wire[2:0]tmds_d_p_0,tmds_d_n_0;
 top_duo01 dut(.*);
 defparam dut.instrument.RESET_TICKS=50000;
 defparam dut.instrument.BOOT_TICKS=50000;
 defparam dut.instrument.RESET_SETUP_TICKS=50000;
 defparam dut.instrument.HOLD_TICKS=20000000;
 bno_two_hand_peer lp(.sensor_rst_n(imu_rst_n[0]),.scl(imu_scl[0]),.sda(imu_sda[0]),.int_n(imu_int_n[0]),.configured(configured[0]));
 bno_two_hand_peer rp(.sensor_rst_n(imu_rst_n[1]),.scl(imu_scl[1]),.sda(imu_sda[1]),.int_n(imu_int_n[1]),.configured(configured[1]));
 task left(input integer angle,down);
  integer z,w;begin z=$rtoi(16384*$sin(angle*3.141592653589793/360));w=$rtoi(16384*$cos(angle*3.141592653589793/360));lp.sensor_report(0,0,z,w,2510-down,0);end
 endtask
 task right(input integer angle,down);
  integer z,w;begin z=$rtoi(16384*$sin(angle*3.141592653589793/360));w=$rtoi(16384*$cos(angle*3.141592653589793/360));rp.sensor_report(0,0,z,w,2510-down,0);end
 endtask
 task pair(input integer la,ra,ld,rd);
  realtime t;begin t=$realtime;fork left(la,ld);right(ra,rd);join
   if($realtime-t>=10000000)$fatal(1,"100Hz pair overloaded");#(10000000-($realtime-t));end
 endtask
 // Decode actual PT8211 output, not the internal PCM valid flag.
 reg ws_old=0;reg[15:0]serial_word=0,expected_left=0,expected_right=0;
 integer bits=0,serial_nonzero=0,words=0;bit decoding=0;
 always @(negedge hp_bck)begin
  #1;
  if(dut.dac.slot==1 && dut.rst_n)begin
   expected_left=dut.dac.held_left;expected_right=dut.dac.held_right;
  end
 end
 always @(posedge hp_bck)if(dut.rst_n)begin
  if(hp_ws!=ws_old)begin
   if(decoding && bits!=16)$fatal(1,"DAC word length %0d",bits);
   ws_old=hp_ws;bits=0;serial_word=0;decoding=1;
  end
  if(decoding)begin
   serial_word={serial_word[14:0],hp_din};bits++;
   if(bits==16)begin
    if(serial_word!==(hp_ws ? expected_left : expected_right))$fatal(1,"LSBJ word mismatch %h",serial_word);
    words++;if(serial_word!=0)serial_nonzero++;
   end
  end
 end
 reg[31:0]right_frequency;
 initial begin
  wait(dut.rst_n);repeat(8)@(negedge clk);
  if(dut.enabled!=0 || !dut.muted || !pa_en || imu_rst_n!==3 || imu_scl!==3 || imu_sda!==3)$fatal(1,"unsafe unenabled board top");
  force dut.keys.enabled=2'b11;force dut.keys.profiles=4'b1000;force dut.keys.chord_mode=1'b1;
  wait(configured==3);pair(0,0,0,0);
  @(negedge clk);force dut.keys.calibrate=2'b11;@(negedge clk);force dut.keys.calibrate=2'b00;
  repeat(55)pair(0,0,0,0);
  if(!dut.status[1] || !dut.status[257])$fatal(1,"board top origins failed");
  $display("PROGRESS 50MHz dual origins calibrated");
  for(integer n=1;n<=7;n++)pair(0,n*10,0,0);repeat(5)pair(0,70,0,0);
  pair(0,70,256,1024);repeat(4)pair(0,70,0,0);
  if(dut.notes[6:0]!=65 || dut.notes[13:7]!=69 || dut.notes[20:14]!=72 || dut.notes[16*7+:7]!=70)$fatal(1,"native board mapping");
  if(!dut.gates[0] || !dut.gates[16])$fatal(1,"audio events not connected");
  if(serial_nonzero || !pa_en)$fatal(1,"muted board leaked audio");
  force dut.keys.muted=1'b0;repeat(4)pair(0,70,0,0);
  if(serial_nonzero==0 || pa_en || dut.gain!=256)$fatal(1,"unmute / actual serial output failed");
  right_frequency=dut.instrument.synth.audio.freq[16];force dut.keys.enabled=2'b10;
  repeat(4)begin realtime t;t=$realtime;right(70,0);#(10000000-($realtime-t));end
  if(dut.gates[15:0]!=0 || dut.instrument.synth.audio.gate[0] || !dut.gates[16] || !dut.online[1] || dut.instrument.synth.audio.freq[16]!=right_frequency)$fatal(1,"board stop crossed hands");
  force dut.keys.muted=1'b1;repeat(4)begin realtime t;t=$realtime;right(70,0);#(10000000-($realtime-t));end
  if(!pa_en || dut.gain!=0 || dut.pcm!=0)$fatal(1,"mute did not drain ramp");
  if(dut.underflows || dut.invalid || dut.drops || dut.overruns)$fatal(1,"production board digital overrun");
  $display("TB_PASS DUO01 50MHz/48kHz board top: native dual I2C 100Hz, separate origins, negative-Z triad/melody, muted PCM, unmute gain ramp, PT8211 decoded %0d words (%0d nonzero), per-hand stop; max render %0d cycles",words,serial_nonzero,dut.max_render);$finish;
 end
 initial begin #1500000000;$fatal(1,"board watchdog");end
endmodule
