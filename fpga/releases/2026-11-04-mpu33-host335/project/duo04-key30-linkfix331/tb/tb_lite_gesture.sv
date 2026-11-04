`timescale 1ns/1ps
module tb_lite_gesture;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,clear=0,enabled=1,invert=0,button_n=1,button2_n=1,pose_valid=0,playable=1,zone_valid=1,hit=0,chord=0,glide_on=1,vibrato_on=0;
 reg signed[15:0]pitch=0;reg[3:0]zone=0,hit_zone=0;reg[1:0]hit_profile=0,hit_octave=0;
 wire pressed,octave_fresh,pending,judging;wire[1:0]octave,hit_octave_snapshot;wire signed[15:0]bend;wire[15:0]serial;wire[55:0]debug_state;
 lite_hand_gesture #(.CLK_HZ(1000000)) d(.glide_ms(9'd80),.*);
 task ms(input integer n);repeat(n*1000)@(negedge clk);endtask
 initial begin
 repeat(3)@(negedge clk);rst_n=1;ms(15);hit=1;@(negedge clk);hit=0;
 button_n=0;ms(210);if(!pressed || octave!=1)$fatal(1,"long C5");
 ms(90);if(bend!=1200)$fatal(1,"slide target %d",bend);
 zone=2;ms(90);if(bend!=1600)$fatal(1,"zone glide %d",bend);
 button_n=1;ms(20);if(bend!=1600)$fatal(1,"release froze wrong pitch");
 vibrato_on=1;pose_valid=1;@(negedge clk);pose_valid=0;pitch=16;pose_valid=1;@(negedge clk);pose_valid=0;ms(2);
 if(bend<1620 || bend>1650)$fatal(1,"motion vibrato %d",bend);
 clear=1;@(negedge clk);clear=0;ms(2);if(bend!=0)$fatal(1,"clear");
 $display("TB_PASS C5 long hold/80ms zone ramp/release frozen pitch/motion vibrato/clear");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
