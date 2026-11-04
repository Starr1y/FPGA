`timescale 1ns/1ps
module tb_fan04_expression_rate; parameter POSE_HZ=100;
    reg stream_reset=0;reg clk=0;always #10 clk=!clk;
    reg rst_n=0,sensor_restarted=0,playable=1,express=0,pose_valid=0;
    reg signed [15:0] roll=0,pitch=0;
    wire signed [15:0] bend_cents,vibrato_cents;wire [7:0] brightness;wire expression_active;
    hand_expression #(.POSE_HZ(POSE_HZ)) dut(.*);
    task report;
        begin @(negedge clk);pose_valid=1;@(negedge clk);pose_valid=0;repeat(2) @(negedge clk);end
    endtask
    integer n,peak_vibrato,frequency,observed;reg [7:0] frozen_brightness;reg signed [15:0] frozen_bend;
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
        // Independently generated sine samples at the declared real report rate.
        // Frequencies 3/5/8/10 must pass; 1/2/12/15 must be rejected.
        for(integer f_index=0;f_index<8;f_index++) begin
            case(f_index)
             0:frequency=1;1:frequency=2;2:frequency=3;3:frequency=5;
             4:frequency=8;5:frequency=10;6:frequency=12;7:frequency=15;
            endcase
            sensor_restarted=1;@(negedge clk);sensor_restarted=0;
            roll=0;pitch=0;express=0;repeat(POSE_HZ)report();express=1;report();
            peak_vibrato=0;observed=0;
            for(n=0;n<POSE_HZ*6;n++) begin
                roll=$rtoi(3*16*$sin(6.283185307179586*frequency*n/POSE_HZ));report();
                if(vibrato_cents< -30 || vibrato_cents>30)$fatal(1,"vibrato limit");
                if(n>POSE_HZ*2 && vibrato_cents!=0)observed++;
                if(vibrato_cents>peak_vibrato)peak_vibrato=vibrato_cents;
            end
            if(frequency>=3 && frequency<=10 && (observed==0 || peak_vibrato<5))
                $fatal(1,"%0dHz report rate failed %0dHz hand tremor peak=%0d",POSE_HZ,frequency,peak_vibrato);
            if((frequency<3 || frequency>10) && observed!=0)
                $fatal(1,"%0dHz report rate accepted %0dHz out-of-band tremor %0d",POSE_HZ,frequency,observed);
            roll=0;repeat(POSE_HZ)report();
            if(vibrato_cents!=0)$fatal(1,"stationary vibrato persists");
            $display("RATE %0d FREQ %0d PEAK %0d ACTIVE %0d",POSE_HZ,frequency,peak_vibrato,observed);
        end
        playable=0;report();if(vibrato_cents!=0 || expression_active) $fatal(1,"offline expression");
        sensor_restarted=1;@(negedge clk);sensor_restarted=0;
        if(bend_cents!=0 || vibrato_cents!=0 || brightness!=128) $fatal(1,"restart expression defaults");
        $display("TB_PASS independent Roll/Pitch, limits, freeze/re-reference, 3/5/8/10Hz accepted and 1/2/12/15Hz rejected at actual declared rate and restart");
        $finish;
    end
    initial begin #10000000;$fatal(1,"test watchdog");end
endmodule
