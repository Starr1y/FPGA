`timescale 1ns/1ps
module tb_ui23_events;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,status_update=0;reg[1055:0]status=0;
 wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 duo04_panel dut(.*);
 task send;begin @(negedge clk);status_update=1;@(negedge clk);status_update=0;repeat(3)@(negedge clk);end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;status[810]=1;status[812:811]=3;status[0]=1;status[256]=1;
  send();if(dut.hit_timer[0]!=0 || dut.hit_timer[1]!=0)$fatal(1,"no strike on initial zero counters");
  status[21:18]=4;send();if(dut.hit_timer[0]!=0)$fatal(1,"selection alone must not strike");
  status[159:128]=1;status[25:22]=2;send();
  if(dut.hit_timer[0]==0 || dut.hit_timer[1]!=0 || dut.last_hit_zone[0]!=2)$fatal(1,"independent left strike at captured zone");
  status[21:18]=6;send();if(dut.last_hit_zone[0]!=2)$fatal(1,"moving selection must not move the strike");
  status[415:384]=1;status[281:278]=4;send();if(dut.hit_timer[1]==0 || dut.last_hit_zone[1]!=4)$fatal(1,"independent right strike");
  status[810]=0;send();if(dut.hit_timer[0]!=0 || dut.hit_timer[1]!=0)$fatal(1,"stop clears both pulses");
  status[810]=1;status[159:128]=0;send();if(dut.hit_timer[0]!=0)$fatal(1,"counter reset is not a strike");
  status[811]=0;status[0]=0;status[159:128]=2;send();if(dut.hit_timer[0]!=0)$fatal(1,"disconnected hand cannot flash");
  status[811]=1;status[0]=1;status[803:802]=3;status[159:128]=3;send();if(dut.hit_timer[0]!=0)$fatal(1,"diagnostics cannot flash");
  if(dut.state_label(256'd0,1'b0)!=dut.L_OFFLINE)$fatal(1,"offline state");
  if(dut.state_label(256'd1,1'b1)!=dut.L_CENTER_WAIT)$fatal(1,"uncentered state");
  if(dut.state_label(256'h397,1'b1)!=dut.L_CENTERING)$fatal(1,"centering overrides ready");
  if(dut.state_label(256'h393,1'b1)!=dut.L_READY)$fatal(1,"ready state");
  if(dut.state_label(256'h3b3,1'b1)!=dut.L_RANGE)$fatal(1,"out of range state");
  if(dut.label_address(dut.L_LEFT,25)!=0)$fatal(1,"labels must not bleed into next row");
  status[928:920]=256;send();if(dut.volume_width!=112)$fatal(1,"full volume bar overflow");
  status[928:920]=128;send();if(dut.volume_width!=56)$fatal(1,"half volume bar overflow");
  status[928:920]=0;send();if(dut.volume_width!=0)$fatal(1,"zero volume bar");
  status[801:800]=1;status[803:802]=0;status[812:811]=0;status[159:128]=4;send();
  if(dut.hit_timer[0]==0 || !dut.link)$fatal(1,"host input must not depend on physical IMU online");
  status[803:802]=3;send();if(dut.link || dut.hit_timer[0]!=0)$fatal(1,"host input must not impersonate an IMU in diagnostics");
  $display("TB_PASS UI23 real-counter strikes, hand isolation, stop/offline/page gates, semantic statuses and label bounds");$finish;
 end
endmodule
