`timescale 1ns/1ps
module tb_keys30;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,clear=0,pose_valid=1,playable=1,zone_valid=1,teaching=0;reg[1:0]key_n=3,profile=0,lesson_octave=0;reg signed[15:0]pitch=0;reg[3:0]zone=3;
 wire event_valid,combo,holding;wire[31:0]payload;wire[1:0]pressed,octave,last_octave;wire[7:0]strength;wire[3:0]blocked;
 s1s2_keys #(.CLK_HZ(1000000)) d(.*);integer notes=0,updates=0;
 always @(posedge clk)if(event_valid)begin if(payload[31:30]==0)notes<=notes+1;else updates<=updates+1;end
 task ms(input integer n);repeat(n*1000)@(negedge clk);endtask
 task tap(input integer angle,input[1:0]expected);begin pitch=angle;ms(10);key_n=2;ms(12);if(last_octave!=expected)$fatal(1,"octave %d expected%d",last_octave,expected);key_n=3;ms(12);end endtask
 initial begin
 repeat(4)@(negedge clk);rst_n=1;ms(10);
 tap(-16,3);tap(0,0);tap(480,0);tap(496,1);
 if(notes!=4 || updates!=4 || strength!=48)$fatal(1,"short strength/repeat");
 key_n=2;ms(240);if(notes!=5 || strength!=112)$fatal(1,"heavy");key_n=3;ms(12);
 key_n=1;ms(20);key_n=0;ms(12);if(!combo || holding)$fatal(1,"combo");ms(200);if(holding)$fatal(1,"consumed combo became expression");key_n=3;ms(12);
 key_n=1;ms(200);if(!holding)$fatal(1,"long S2");key_n=0;ms(12);if(combo)$fatal(1,"long treated as combo");key_n=3;ms(12);
 pose_valid=0;ms(20);key_n=2;ms(12);if(blocked!=1)$fatal(1,"stale admitted");key_n=3;ms(12);
 clear=1;ms(1);clear=0;
 $display("TB_PASS S1 octave boundaries/once/strength/S2 ordered combo/long discrimination/stale pose");$finish;
 end
 initial begin #40000000;$fatal(1,"timeout");end
endmodule
