`timescale 1ns/1ps
// Native SH2 quaternion bytes -> decoder -> actual pose conversion -> cadence guard -> expression.
// Sampling timestamps remain 10ms apart while simulation arrival is deliberately compressed.
module tb_pose_expression_path;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,packet_ready=0;
 reg [9:0]packet_length=21;reg [7:0]memory[0:511];reg[31:0]packet_hint_ticks=1000;
 wire packet_take;wire [8:0]read_addr;wire[7:0]read_data=memory[read_addr];
 reg packet_hint_valid=1;wire quat_valid;wire[7:0]quat_sequence;wire[31:0]quat_timestamp_ticks;wire quat_timestamp_valid;
 wire signed[15:0]qx,qy,qz,qw;wire[1:0]accuracy;
 wire pose_valid;wire signed[15:0]yaw,pitch,roll;wire[7:0]pose_sequence;wire[31:0]pose_timestamp_ticks;wire pose_timestamp_valid;
 wire sample_valid,stream_reset;wire signed[15:0]sample_roll,sample_pitch;wire[15:0]discontinuities;
 wire signed[15:0]bend_cents,vibrato_cents;wire[7:0]brightness;wire expression_active;
 reg express=0;integer cargo_seq=0,seq=0,n,peak=0;integer accepted=0;
 shtp_report_decode decoder(.clk(clk),.rst_n(rst_n),.packet_ready(packet_ready),.packet_length(packet_length),
  .packet_hint_ticks(packet_hint_ticks),.packet_hint_valid(packet_hint_valid),.linear_ready(1'b1),
  .packet_take(packet_take),.read_addr(read_addr),.read_data(read_data),
  .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),
  .quat_sequence(quat_sequence),.quat_timestamp_ticks(quat_timestamp_ticks),.quat_timestamp_valid(quat_timestamp_valid));
 quaternion_pose pose(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.online(1'b1),.calibrate(1'b0),
  .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.gx(16'sd0),.gy(16'sd0),.gz(16'sd0),
  .quat_sequence(quat_sequence),.quat_timestamp_ticks(quat_timestamp_ticks),.quat_timestamp_valid(quat_timestamp_valid),
  .pose_valid(pose_valid),.yaw(yaw),.pitch(pitch),.roll(roll),.pose_sequence(pose_sequence),.pose_timestamp_ticks(pose_timestamp_ticks),.pose_timestamp_valid(pose_timestamp_valid));
 expression_stream_guard #(.CLK_HZ(1000000)) guard(.clk(clk),.rst_n(rst_n),.clear(1'b0),.enabled(1'b1),.pose_valid(pose_valid),.roll(roll),.pitch(pitch),
  .pose_sequence(pose_sequence),.pose_timestamp_ticks(pose_timestamp_ticks),.pose_timestamp_valid(pose_timestamp_valid),
  .sample_valid(sample_valid),.sample_roll(sample_roll),.sample_pitch(sample_pitch),.stream_reset(stream_reset),.discontinuities(discontinuities));
 hand_expression expression(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.playable(1'b1),.express(express),.stream_reset(stream_reset),
  .pose_valid(sample_valid),.roll(sample_roll),.pitch(sample_pitch),.bend_cents(bend_cents),.vibrato_cents(vibrato_cents),.brightness(brightness),.expression_active(expression_active));
 always @(posedge clk)if(sample_valid)accepted++;
 task report(input real angle);
  integer x,w;reg[31:0]expected_ts;
  begin
   x=$rtoi(16384*$sin(angle*3.141592653589793/360));w=$rtoi(16384*$cos(angle*3.141592653589793/360));
   for(integer k=0;k<512;k++)memory[k]=0;
   memory[0]=21;memory[2]=3;memory[3]=cargo_seq;cargo_seq++;
   // The base is -200 ticks and report delay is +100: sample is hint -100.
   memory[4]=8'hfb;memory[5]=200;memory[9]=8'h08;memory[10]=seq;memory[11]=3;memory[12]=100;
   memory[13]=x;memory[14]=x>>>8;memory[19]=w;memory[20]=w>>>8;
   packet_hint_ticks+=100;expected_ts=packet_hint_ticks-100;
   @(negedge clk);packet_ready=1;wait(packet_take);@(negedge clk);packet_ready=0;
   wait(pose_valid);@(negedge clk);
   if(pose_sequence!==seq[7:0] || pose_timestamp_ticks!==expected_ts || pose_timestamp_valid!==packet_hint_valid)
    $fatal(1,"metadata did not follow its quaternion through pose pipeline seq=%h ts=%d",pose_sequence,pose_timestamp_ticks);
   seq++;repeat(12)@(negedge clk);
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(20)report(0);express=1;report(0);
  for(n=0;n<400;n++)begin
   report(3*$sin(6.283185307179586*5*n/100));
   if(n>200 && vibrato_cents>peak)peak=vibrato_cents;
  end
  if(peak<5 || discontinuities!=0 || accepted<400 || !expression_active)
   $fatal(1,"native 100Hz metadata path lost tremor peak=%0d faults=%0d samples=%0d",peak,discontinuities,accepted);
  seq++;report(20);
  if(vibrato_cents || expression_active || discontinuities!=1)$fatal(1,"gap did not reset expression");
  repeat(20)report(20);
  if(vibrato_cents || bend_cents< -1 || bend_cents>1)$fatal(1,"recovery created fake expression");
  packet_hint_valid=0;report(20);
  if(vibrato_cents || expression_active || discontinuities!=2)$fatal(1,"untrusted metadata accepted");
  packet_hint_valid=1;repeat(4)report(20);
  repeat(50010)@(negedge clk);
  if(vibrato_cents || expression_active || discontinuities!=3)$fatal(1,"stale expression persisted");
  $display("TB_PASS native SH2 quaternion base/delay/sequence metadata survives real pose pipeline, 5Hz tremor at 100Hz burst arrival, gap/invalid/silence suppression and neutral recovery");$finish;
 end
 initial begin #10000000;$fatal(1,"native expression watchdog");end
endmodule
