`timescale 1ns/1ps
module tb_duo04_32;
reg clk=0;always #10 clk=~clk;reg rst_n=0,sample_tick=0;integer fraction=0;
always @(posedge clk)begin sample_tick<=0;if(rst_n)begin if(fraction>=49952000)begin fraction<=fraction+48000-50000000;sample_tick<=1;end else fraction<=fraction+48000;end end
reg event_valid=0;wire event_ready;reg[63:0]event_data=0;reg[1:0]release_pending=0;reg[63:0]epochs=0;wire[1:0]release_ack;
wire[31:0]active,gates,underflows;wire committed,valid;wire[15:0]max_render;reg[47:0]glide=0;
two_hand_synth #(.VOICES(32),.ENABLE_EXPRESSION(1)) dut(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
.release_pending(release_pending),.release_ack(release_ack),.epochs(epochs),.chord_mode(1'b0),.preset_ids({3'd3,3'd0}),.release_ids(4'b0),.hold_samples_left(32'd240000),.hold_samples_right(32'd240000),
.piano_hold(2'b11),.piano_coefficients({16'd134,16'd134}),.bend_cents(32'b0),.vibrato_cents(32'b0),.brightness(16'h8080),.glide_coefficients(glide),.vibrato_ratios({20'd65536,20'd65536}),
.active_voices(active),.gates(gates),.underflows(underflows),.committed(committed),.sample_valid(valid),.max_render_cycles(max_render),.monitor_voice(5'd0));
task strike(input integer id,hand,zone);
begin wait(event_ready);@(negedge clk);event_data=0;event_data[11:4]=id;event_data[20:14]=96;event_data[29]=hand;event_data[28:25]=zone;event_valid=1;@(negedge clk);event_valid=0;wait(committed);@(negedge clk);end endtask
initial begin
repeat(10)@(negedge clk);rst_n=1;
for(integer i=0;i<32;i++)strike(i+1,i>=16,i%7);
repeat(10)@(posedge valid);if(active!==32'hffffffff || underflows || max_render>=1040)$fatal(1,"32 voice starvation %d",max_render);
glide[23:0]=2331;strike(33,0,4);repeat(600)@(posedge valid);
if($countones(gates[15:0])!=1 || gates[31:16]!=16'hffff || underflows)$fatal(1,"mono glide disturbed other hand");
epochs={32'd1,32'd1};release_pending=3;wait(release_ack==3);@(negedge clk);release_pending=0;repeat(600)@(posedge valid);
if(active || underflows)$fatal(1,"stop failed");
$display("TB_PASS 32 mixed piano/plucked with expression pipeline, max render %d clocks; optional mono only owning hand; stop",max_render);$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
