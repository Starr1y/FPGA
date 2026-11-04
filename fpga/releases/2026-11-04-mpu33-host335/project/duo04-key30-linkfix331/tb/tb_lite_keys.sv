`timescale 1ns/1ps
module tb_lite_keys;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,clear=0,consume=0;reg[1:0]key_n=3;
 wire[1:0]octave,pressed;wire holding,pending,judging;
 performance_hand_keys #(.CLK_HZ(1000)) dut(.*);
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
 cycles(3);rst_n=1;cycles(15);
 key_n=2;cycles(30);key_n=3;cycles(15);
 if(!pending || octave!=1)$fatal(1,"short high");
 consume=1;cycles(1);consume=0;cycles(2);if(pending || octave!=0)$fatal(1,"one shot");
 key_n=1;cycles(210);if(!holding || octave!=3 || pending)$fatal(1,"long low");
 key_n=0;cycles(15);if(!holding || octave!=0)$fatal(1,"both middle");
 key_n=3;cycles(15);if(holding || pending)$fatal(1,"long release retrigger");
 key_n=0;cycles(30);key_n=3;cycles(15);if(pending || octave!=0)$fatal(1,"short cancel");
 key_n=2;clear=1;cycles(3);clear=0;cycles(220);if(holding || pending)$fatal(1,"held after clear");
 key_n=3;cycles(15);key_n=1;cycles(30);key_n=3;cycles(15);if(!pending || octave!=3)$fatal(1,"rearm low");
 $display("TB_PASS short/long/both/consume/clear/rearm");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
