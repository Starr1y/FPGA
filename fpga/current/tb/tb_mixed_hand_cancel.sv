`timescale 1ns/1ps
module tb_mixed_hand_cancel;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,left_up=1,right_up=1,left_hit=0,right_hit=0,ready=0;reg[1:0]ack=0;
 wire[1:0]online_driven={right_up,left_up},notes_driven={right_hit,left_hit};
 wire valid;wire[63:0]data,epochs,cancelled,drops;wire[1:0]release_pending;integer events=0,left_events=0,right_events=0;
 two_hand_i2c_core #(.CLK_HZ(1000000),.RIGHT_IMU_UART(1)) d(.clk(clk),.rst_n(rst_n),.enabled(2'b11),.force_reset(2'b0),.calibrate(2'b0),.express(2'b0),.mirror(2'b0),
 .layout_profile(4'b0),.scl_in(2'b11),.sda_in(2'b11),.int_n(2'b11),.wrist_enable(2'b0),.wrist_fresh(2'b0),.wrist_octaves(4'b0),
 .event_valid(valid),.event_ready(ready),.event_data(data),.epochs(epochs),.release_pending(release_pending),.release_ack(ack),.cancelled_events(cancelled),.event_drops(drops));
 always @(posedge clk)if(valid&&ready)begin
  events=events+1;
  if(data[29])begin right_events=right_events+1;if(data[63:32]!=1)$fatal(1,"right epoch after reconnect");end
  else begin left_events=left_events+1;if(data[63:32]!=0)$fatal(1,"right disconnect changed left epoch");end
 end
 initial begin
  force d.online=online_driven;force d.note_on=notes_driven;force d.sensor_restarted=2'b0;force d.velocity_update=2'b0;
  force d.hit_zone=8'h43;force d.hit_profile=4'b0;force d.hit_octave=4'b0;force d.velocity=16'h4040;force d.reason=4'b0101;force d.event_id=16'h0101;
  repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  if(d.hand[0].endpoint.EXTERNAL_STREAM!=0||d.hand[1].endpoint.EXTERNAL_STREAM!=1)$fatal(1,"wrong hand source selection");
  left_hit=1;@(negedge clk);left_hit=0;@(negedge clk);right_hit=1;@(negedge clk);right_hit=0;
  @(negedge clk);right_up=0;repeat(4)@(negedge clk);
  if(!release_pending[1]||release_pending[0]||epochs!==64'h0000000100000000)$fatal(1,"wrong per-hand cancellation");
  ack=2;@(negedge clk);ack=0;ready=1;repeat(12)@(negedge clk);
  if(events!=1||left_events!=1||right_events!=0||cancelled[63:32]==0)$fatal(1,"old right note leaked or left note lost");
  left_hit=1;@(negedge clk);left_hit=0;repeat(8)@(negedge clk);
  if(left_events!=2)$fatal(1,"left stopped with right offline");
  right_up=1;repeat(4)@(negedge clk);right_hit=1;@(negedge clk);right_hit=0;repeat(8)@(negedge clk);
  if(right_events!=1||drops!=0)$fatal(1,"right reconnect didn't use independent queue");
  $display("TB_PASS left BNO/right UART selection, independent epochs, right cancellation, left continuity and reconnect");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
