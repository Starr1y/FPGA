`timescale 1ns/1ps
module tb_hand_expression;
    reg clk=0;always #10 clk=!clk;
    reg rst_n=0,sensor_restarted=0,playable=1,express=0,pose_valid=0;
    reg signed [15:0] roll=0,pitch=0;
    wire signed [15:0] bend_cents,vibrato_cents;wire [7:0] brightness;wire expression_active;
    hand_expression dut(.*);
    task report;
        begin @(negedge clk);pose_valid=1;@(negedge clk);pose_valid=0;repeat(2) @(negedge clk);end
    endtask
    integer n,peak_vibrato;reg [7:0] frozen_brightness;reg signed [15:0] frozen_bend;
    initial begin
        repeat(5) @(negedge clk);rst_n=1;repeat(10) report();
        express=1;report();
        roll=20*16;repeat(300) report();
        if(bend_cents<158 || bend_cents>161 || brightness!=128 || vibrato_cents!=0)
            $fatal(1,"Roll did not change only bend: bend=%0d bright=%0d vib=%0d",bend_cents,brightness,vibrato_cents);
        pitch=20*16;repeat(100) report();
        if(brightness<205 || brightness>210 || bend_cents<158 || bend_cents>161)
            $fatal(1,"Pitch did not change only brightness");
        roll=100*16;repeat(300) report();
        if(bend_cents!=200) $fatal(1,"bend limit");
        express=0;report();frozen_brightness=brightness;frozen_bend=bend_cents;
        roll=-30*16;pitch=-30*16;repeat(100) report();
        if(brightness!=frozen_brightness || bend_cents!=frozen_bend || vibrato_cents!=0)
            $fatal(1,"release did not retain bend and brightness");
        roll=0;pitch=0;repeat(300) report();express=1;report();repeat(100) report();
        if(bend_cents< -1 || bend_cents>1) $fatal(1,"new expression zero reference");
        // Reference stream is 200Hz. A 5Hz hand motion has 40 samples/period.
        peak_vibrato=0;
        for(n=0;n<400;n++) begin
            roll=$rtoi(3*16*$sin(6.283185307179586*n/40));report();
            if(vibrato_cents< -30 || vibrato_cents>30) $fatal(1,"vibrato exceeds safety limit");
            if(vibrato_cents>peak_vibrato) peak_vibrato=vibrato_cents;
        end
        if(peak_vibrato<10) $fatal(1,"actual 5Hz hand motion not detected peak=%0d crossings=%0d",peak_vibrato,dut.good_crossings);
        roll=0;repeat(100) report();
        if(vibrato_cents!=0) $fatal(1,"stationary hand has persistent vibrato");
        peak_vibrato=0;
        for(n=0;n<600;n++) begin
            roll=$rtoi(3*16*$sin(6.283185307179586*n/200));report();
            if(n>200 && vibrato_cents!=0) $fatal(1,"slow 1Hz movement misclassified as hand vibrato");
        end
        playable=0;report();if(vibrato_cents!=0 || expression_active) $fatal(1,"offline expression");
        sensor_restarted=1;@(negedge clk);sensor_restarted=0;
        if(bend_cents!=0 || vibrato_cents!=0 || brightness!=128) $fatal(1,"restart expression defaults");
        $display("TB_PASS independent Roll/Pitch, limits, freeze/re-reference, real 5Hz motion, 1Hz rejection and restart");
        $finish;
    end
    initial begin #1000000;$fatal(1,"test watchdog");end
endmodule
