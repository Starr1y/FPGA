// Pose reports requested at 200Hz. Fixed-point filters retain 8 fractional
// bits beyond Q4 angles. Bend +/-200 cents; real-motion vibrato +/-30 cents.
module hand_expression(
    input clk,input rst_n,input sensor_restarted,input playable,input express,
    input pose_valid,input signed [15:0] roll,pitch,
    output reg signed [15:0] bend_cents,output reg signed [15:0] vibrato_cents,
    output reg [7:0] brightness,output reg expression_active
);
    reg signed [31:0] slow_roll,pitch_lp,high_base,bandpass;
    reg signed [31:0] roll_sample,pitch_sample,work_slow,work_pitch,work_base,work_band;
    reg [1:0] state;
    reg signed [31:0] reference_roll,reference_pitch;
    reg [7:0] reference_brightness;
    reg express_old,filters_ready,polarity;
    reg [7:0] half_period;
    reg [2:0] good_crossings;
    wire signed [31:0] roll_q=$signed(roll)*256;
    wire signed [31:0] pitch_q=$signed(pitch)*256;
    wire signed [31:0] bend_target=(work_slow-reference_roll)>>>9;
    wire signed [31:0] vibrato_target=(work_band*10)>>>12;
    wire signed [31:0] brightness_target=$signed({1'b0,reference_brightness})+((work_pitch-reference_pitch)>>>10);
    wire crossing=(work_band>1229 && !polarity) || (work_band< -1229 && polarity);
    function signed [15:0] bounded_bend;
        input signed [31:0] value;
        begin bounded_bend=value>200 ? 200 : value< -200 ? -200 : value;end
    endfunction
    function signed [15:0] bounded_vibrato;
        input signed [31:0] value;
        begin bounded_vibrato=value>30 ? 30 : value< -30 ? -30 : value;end
    endfunction
    function [7:0] bounded_brightness;
        input signed [31:0] value;
        begin bounded_brightness=value>255 ? 255 : value<0 ? 0 : value;end
    endfunction
    wire [7:0] target_brightness=bounded_brightness(brightness_target);
    wire signed [9:0] brightness_delta=$signed({1'b0,target_brightness})-$signed({1'b0,brightness});
    always @(posedge clk) begin
        if(!rst_n) begin
            slow_roll<=0;pitch_lp<=0;high_base<=0;bandpass<=0;
            roll_sample<=0;pitch_sample<=0;work_slow<=0;work_pitch<=0;work_base<=0;work_band<=0;state<=0;
            reference_roll<=0;reference_pitch<=0;reference_brightness<=128;
            express_old<=0;filters_ready<=0;polarity<=0;half_period<=0;good_crossings<=0;
            bend_cents<=0;vibrato_cents<=0;brightness<=128;expression_active<=0;
        end else begin
            express_old<=express && playable;
            expression_active<=express && playable;
            if(!express || !playable) begin vibrato_cents<=0;good_crossings<=0;half_period<=0;end
            if(express && playable && !express_old) begin
                reference_roll<=slow_roll;reference_pitch<=pitch_lp;reference_brightness<=brightness;
                bend_cents<=0;vibrato_cents<=0;good_crossings<=0;half_period<=0;
            end
            case(state)
              0:if(pose_valid) begin roll_sample<=roll_q;pitch_sample<=pitch_q;state<=1;end
              1:begin
                work_slow<=slow_roll+((roll_sample-slow_roll)>>>5);
                work_pitch<=pitch_lp+((pitch_sample-pitch_lp)>>>3);
                work_base<=high_base+(((roll_sample-high_base)*23)>>>8);state<=2;
              end
              2:begin work_band<=bandpass+(((roll_sample-work_base-bandpass)*69)>>>8);state<=3;end
              3:begin
                state<=0;
                if(!filters_ready) begin
                    slow_roll<=roll_sample;pitch_lp<=pitch_sample;high_base<=roll_sample;bandpass<=0;filters_ready<=1;
                end else begin slow_roll<=work_slow;pitch_lp<=work_pitch;high_base<=work_base;bandpass<=work_band;end
                if(express && playable && express_old && filters_ready) begin
                    bend_cents<=bounded_bend(bend_target);
                    // A minimum one-unit step avoids integer deadband at the
                    // end of a brightness ramp, without changing initial gain.
                    if(brightness_delta!=0) brightness<=brightness+
                        (brightness_delta>0 && brightness_delta<4 ? 1 :
                         brightness_delta<0 && brightness_delta> -4 ? -1 : brightness_delta>>>2);
                    if(half_period<255) half_period<=half_period+1'b1;
                    if(crossing) begin
                        polarity<=work_band>0;half_period<=0;
                        if(half_period>=9 && half_period<=34) begin
                            if(good_crossings<3) good_crossings<=good_crossings+1'b1;
                        end else good_crossings<=0;
                    end
                    if(half_period>40) good_crossings<=0;
                    if(good_crossings>=3 && half_period<=40 && (work_band>1229 || work_band< -1229))
                        vibrato_cents<=bounded_vibrato(vibrato_target);
                    else vibrato_cents<=0;
                end
              end
            endcase
            if(sensor_restarted) begin
                filters_ready<=0;express_old<=0;expression_active<=0;state<=0;
                bend_cents<=0;vibrato_cents<=0;brightness<=128;good_crossings<=0;half_period<=0;
            end
        end
    end
endmodule
