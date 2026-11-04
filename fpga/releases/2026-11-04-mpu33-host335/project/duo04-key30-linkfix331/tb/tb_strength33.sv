`timescale 1ns/1ps
module tb_strength33;
reg clk=0;always #5 clk=~clk;reg rst_n=0;reg[1:0]key_n=3;wire ev;wire[31:0]payload;wire[7:0]strength;integer onsets=0,updates=0;
s1s2_keys #(.CLK_HZ(1000)) d(.clk(clk),.rst_n(rst_n),.clear(1'b0),.key_n(key_n),.pose_valid(1'b1),.playable(1'b1),.zone_valid(1'b1),.pitch(16'sd0),.zone(4'd3),.profile(2'd0),.teaching(1'b0),.lesson_octave(2'd0),.event_valid(ev),.payload(payload),.strength(strength));
always @(posedge clk)if(ev)begin if(payload[31:30]==0)begin onsets=onsets+1;if(payload[20:14]!=48)$fatal(1,"onset not light");end else begin updates=updates+1;if(payload[20:14]!=112)$fatal(1,"update not heavy");end end
initial begin repeat(5)@(negedge clk);rst_n=1;repeat(15)@(negedge clk);key_n=2;repeat(100)@(negedge clk);key_n=3;repeat(15)@(negedge clk);if(onsets!=1||updates!=0||strength!=48)$fatal(1,"short press");key_n=2;repeat(250)@(negedge clk);if(onsets!=2||updates!=1||strength!=112)$fatal(1,"long press");repeat(250)@(negedge clk);if(onsets!=2||updates!=1)$fatal(1,"repeat");$display("TB_PASS immediate light48,short stays light,long220ms heavy112,no retrigger");$finish;end
endmodule
