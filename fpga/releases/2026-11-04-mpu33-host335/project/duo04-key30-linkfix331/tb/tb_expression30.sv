`timescale 1ns/1ps
module tb_expression30;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,clear=0,enabled=1,invert=0,button_n=1,button2_n=1,pose_valid=0,playable=1,zone_valid=1,hit=0,chord=0,glide_on=1,vibrato_on=0,teaching=0;
 reg signed[15:0]pitch=0;reg[3:0]zone=0,hit_zone=0;reg[1:0]hit_profile=0,hit_octave=0,input_profile=0,lesson_octave=0;
 wire pressed,octave_fresh,pending,judging,button_event,combo_active;wire[31:0]button_payload;wire[1:0]octave,hit_octave_snapshot;wire signed[15:0]bend;wire[15:0]serial;wire[55:0]debug_state;
 lite_hand_gesture #(.CLK_HZ(1000000)) d(.glide_ms(9'd80),.*);integer i;
 task ms(input integer n);repeat(n*1000)@(negedge clk);endtask
 task report(input integer p);begin pitch=p;pose_valid=1;@(negedge clk);pose_valid=0;ms(5);end endtask
 initial begin
 repeat(3)@(negedge clk);rst_n=1;report(0);ms(10);hit=1;@(negedge clk);hit=0;
 button2_n=0;for(i=0;i<40;i=i+1)report(0);
 if(!pressed || bend!=0)$fatal(1,"long baseline jump");
 for(i=0;i<55;i=i+1)report(400);
 if(bend<950 || bend>1010)$fatal(1,"sustained pitch cancelled %d",bend);
 zone=2;for(i=0;i<20;i=i+1)report(400);if(bend<950)$fatal(1,"cross-zone changed expression");
 button2_n=1;ms(15);if(bend<950)$fatal(1,"release lost pitch");
 button2_n=0;for(i=0;i<4;i=i+1)report(400);button_n=0;for(i=0;i<4;i=i+1)report(400);
 if(!combo_active)$fatal(1,"combo not recognized");button_n=1;button2_n=1;for(i=0;i<24;i=i+1)report(400);
 if(bend!=400)$fatal(1,"confirmed target slide %d",bend);
 clear=1;@(negedge clk);clear=0;ms(2);if(bend!=0)$fatal(1,"clear");
 $display("TB_PASS S2 baseline/no jump/sustained linear pitch/no intermediate zone slide/confirmed glide/release freeze");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
