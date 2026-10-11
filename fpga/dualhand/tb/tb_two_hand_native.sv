`timescale 1ns/1ps
// Native pin-level peers, 1MHz configured clock / 250kHz I2C / 100Hz reports.
// Human timing stays in seconds; no internal FPGA state is forced.
module tb_two_hand_native;
 reg clk=0;always #500 clk=~clk;reg rst_n=0;
 reg[1:0]enabled=0,force_reset=0,calibrate=0,express=0,mirror=0;
 reg[3:0]layout_profile=4'b0100;
 tri1[1:0]scl,sda,sensor_reset_n;wire[1:0]int_n,configured,scl_low,sda_low,reset_low,online;
 wire[511:0]status;wire[95:0]report_rates;wire[63:0]processing_overruns;
 wire event_valid;reg event_ready=1;wire[63:0]event_data,epochs,event_drops,cancelled_events;
 wire[1:0]release_pending;reg[1:0]release_ack=3;
 for(genvar h=0;h<2;h++)begin
  assign scl[h]=scl_low[h] ? 1'b0 : 1'bz;
  assign sda[h]=sda_low[h] ? 1'b0 : 1'bz;
  assign sensor_reset_n[h]=reset_low[h] ? 1'b0 : 1'bz;
 end
 two_hand_i2c_core #(.CLK_HZ(1000000),.HALF_DIV(2),.RESET_TICKS(1000),.BOOT_TICKS(1000),.RESET_SETUP_TICKS(1000)) dut(
  .clk(clk),.rst_n(rst_n),.enabled(enabled),.force_reset(force_reset),.calibrate(calibrate),.express(express),.mirror(mirror),
  .layout_profile(layout_profile),.scl_in(scl),.sda_in(sda),.int_n(int_n),.scl_low(scl_low),.sda_low(sda_low),.reset_low(reset_low),.online(online),
  .status(status),.report_rates(report_rates),.processing_overruns(processing_overruns),
  .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),.release_pending(release_pending),.release_ack(release_ack),
  .epochs(epochs),.event_drops(event_drops),.cancelled_events(cancelled_events));
 bno_two_hand_peer left_peer(.sensor_rst_n(sensor_reset_n[0]),.scl(scl[0]),.sda(sda[0]),.int_n(int_n[0]),.configured(configured[0]));
 bno_two_hand_peer right_peer(.sensor_rst_n(sensor_reset_n[1]),.scl(scl[1]),.sda(sda[1]),.int_n(int_n[1]),.configured(configured[1]));
 integer notes[0:1],updates[0:1],last_zone[0:1],last_profile[0:1],last_id[0:1],simultaneous=0;
 always @(posedge clk)if(rst_n)begin
  if(dut.note_on==3)simultaneous++;
  if(event_valid && event_ready)begin
   if(event_data[63:32] !== epochs[event_data[29]*32+:32])$fatal(1,"stale epoch delivered");
   if(event_data[31:30]==0)begin
    notes[event_data[29]]++;last_zone[event_data[29]]=event_data[28:25];last_profile[event_data[29]]=event_data[24:23];last_id[event_data[29]]=event_data[11:4];
    if(event_data[20:14]<32 || event_data[13:12]==0)$fatal(1,"native note missing velocity/direction reason");
   end else begin
    updates[event_data[29]]++;
    if(event_data[11:4]!=last_id[event_data[29]])$fatal(1,"strength update applied to another hand/event");
   end
  end
 end
 task left(input integer yaw_angle,input integer down);
  integer z,w;
  begin
   z=$rtoi(16384*$sin(yaw_angle*3.141592653589793/360));w=$rtoi(16384*$cos(yaw_angle*3.141592653589793/360));
   left_peer.sensor_report(0,0,z,w,2510-down,0);
  end
 endtask
 task right(input integer yaw_angle,input integer down);
  integer z,w;
  begin
   z=$rtoi(16384*$sin(yaw_angle*3.141592653589793/360));w=$rtoi(16384*$cos(yaw_angle*3.141592653589793/360));
   right_peer.sensor_report(0,0,z,w,2510-down,0);
  end
 endtask
 task pair(input integer l_angle,input integer r_angle,input integer l_down,input integer r_down);
  realtime began;
  begin
   began=$realtime;fork left(l_angle,l_down);right(r_angle,r_down);join
   if($realtime-began>=10000000)$fatal(1,"two native transfers exceeded 100Hz period");
   #(10000000-($realtime-began));
  end
 endtask
 task right_only(input integer angle,input integer down);
  realtime began;
  begin began=$realtime;right(angle,down);#(10000000-($realtime-began));end
 endtask
 task right_expression(input integer angle,input integer roll_angle,input integer pitch_angle);
  real cy,sy,cr,sr,cp,sp;integer x,y,z,w;realtime began;
  begin
   cy=$cos(angle*3.141592653589793/360);sy=$sin(angle*3.141592653589793/360);
   cr=$cos(roll_angle*3.141592653589793/360);sr=$sin(roll_angle*3.141592653589793/360);
   cp=$cos(pitch_angle*3.141592653589793/360);sp=$sin(pitch_angle*3.141592653589793/360);
   x=$rtoi(16384*(cy*cp*sr-sy*sp*cr));y=$rtoi(16384*(cy*sp*cr+sy*cp*sr));
   z=$rtoi(16384*(sy*cp*cr-cy*sp*sr));w=$rtoi(16384*(cy*cp*cr+sy*sp*sr));
   began=$realtime;right_peer.sensor_report(x,y,z,w,2510,0);#(10000000-($realtime-began));
  end
 endtask
 task request_origin(input reg[1:0]which);
  begin @(negedge clk);calibrate=which;@(negedge clk);calibrate=0;end
 endtask
 reg[31:0]right_epoch;integer before_right,after_left,right_packets;
 initial begin
  for(integer h=0;h<2;h++)begin notes[h]=0;updates[h]=0;last_zone[h]=-1;last_profile[h]=-1;last_id[h]=0;end
  repeat(5)@(negedge clk);rst_n=1;enabled=3;wait(configured==3);
  pair(30,-40,0,0);if(online!=3)$fatal(1,"independent native hosts not online");
  request_origin(3);repeat(55)pair(30,-40,0,0);
  if(!status[1] || !status[257] || processing_overruns!=0)$fatal(1,"independent native origins failed");
  for(integer n=1;n<=5;n++)pair(30+n*10,-40-n*10,0,0);
  repeat(5)pair(80,-90,0,0);
  if(status[21:18]!=5 || status[277:274]!=1 || !status[3] || !status[259])$fatal(1,"relative fan/layout cross-talk L=%0d R=%0d",status[21:18],status[277:274]);
  pair(80,-90,256,-64); // left pure negative-Z jerk; right positive Z, no hit
  if(notes[0]!=1 || notes[1]!=0 || last_zone[0]!=5 || last_profile[0]!=0)$fatal(1,"independent directional event ownership");
  for(integer n=3;n>=0;n--)pair(80,-90,0,-n*16);
  repeat(16)pair(80,-90,0,0);
  event_ready=0;pair(80,-90,1024,1024);repeat(2)pair(80,-90,0,0);
  event_ready=1;repeat(15)pair(80,-90,0,0);
  if(notes[0]!=2 || notes[1]!=1 || last_zone[1]!=1 || last_profile[1]!=1 || updates[0]!=2 || updates[1]!=1 || simultaneous<1 || event_drops!=0)
   $fatal(1,"simultaneous native hit / strength updates lost or mixed L=%0d R=%0d simultaneous=%0d",notes[0],notes[1],simultaneous);
  right_epoch=epochs[63:32];right_packets=status[431:416];before_right=notes[1];
  @(negedge clk);force_reset=1;@(negedge clk);force_reset=0;
  repeat(60)right_only(-90,0);
  if(!online[1] || !status[257] || epochs[63:32]!=right_epoch || status[431:416]<=right_packets || notes[1]!=before_right)
   $fatal(1,"left reset changed right host/origin/epoch");
  right_only(-90,256);repeat(15)right_only(-90,0);
  if(notes[1]!=before_right+1 || last_zone[1]!=1)$fatal(1,"healthy hand failed during peer outage");
  // Full four-bit zone and layout survive the transport into the event queue.
  layout_profile[3:2]=2;
  // Right origin is -40 degrees: absolute +30 is relative +70.
  for(integer n=1;n<=12;n++)right_only(-90+n*10,0);
  repeat(6)right_only(30,0);right_only(30,1024);repeat(15)right_only(30,0);
  if(last_zone[1]!=10 || last_profile[1]!=2)$fatal(1,"twelve-zone event lost: yaw=%0d zone=%0d profile=%0d",$signed(status[303:288]),last_zone[1],last_profile[1]);
  express=2;repeat(2)right_expression(30,0,0);
  repeat(100)right_expression(30,20,0);
  if($signed(status[351:336])<154 || $signed(status[351:336])>164 || status[375:368]!=128 || status[119:112]!=128)
   $fatal(1,"right Roll expression changed pitch brightness or other hand bend=%0d bright=%0d",$signed(status[351:336]),status[375:368]);
  repeat(100)right_expression(30,20,20);
  if(status[375:368]<200 || status[375:368]>214 || $signed(status[351:336])<154 || $signed(status[351:336])>164 || status[119:112]!=128)
   $fatal(1,"right Pitch expression changed Roll/other hand");
  express=0;repeat(15)right_expression(30,0,0);
  if(status[367:352]!=0 || $signed(status[351:336])<154 || status[375:368]<200)$fatal(1,"release lost expression hold");
  // Mirror changes cancel only this group and require a fresh origin.
  mirror[1]=1;right_only(30,0);repeat(55)right_only(30,0);
  if(!status[257])$fatal(1,"mirror change did not re-establish own origin");
  for(integer n=1;n<=5;n++)right_only(30+n*10,0);
  repeat(6)right_only(80,0);right_only(80,1024);repeat(15)right_only(80,0);
  if(last_zone[1]!=2 || last_profile[1]!=2 || $signed(status[303:288])> -49*16 || $signed(status[303:288])< -51*16)
   $fatal(1,"mirrored relative yaw failed");
  right_epoch=epochs[63:32];
  after_left=notes[0];enabled[0]=0;repeat(5)right_only(80,0);
  if(scl_low[0] || sda_low[0] || reset_low[0] || notes[0]!=after_left || epochs[63:32]!=right_epoch || !online[1])
   $fatal(1,"disabled hand drove pads or affected healthy group");
  if(event_drops || processing_overruns)$fatal(1,"dual path overrun");
  $display("TB_PASS two native 0x4A buses autonomous configuration, independent origins/layouts/yaw, negative-Z jerk, simultaneous hit buffering, per-hand strength IDs, left reset/outage/disable isolation, four-bit zone10, independent Roll/Pitch expression and release hold, mirror/re-origin, release epochs; clock-scaled simulation only");$finish;
 end
 initial begin #8000000000;$fatal(1,"native dual-hand watchdog");end
endmodule
