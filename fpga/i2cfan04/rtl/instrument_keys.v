// Dock USER_BUTTON0/1/2, active low. KEY0 calibrates a connected IMU or
// auditions the selected zone offline; hold KEY1 1.5s to reset the sensor;
// KEY2 is the expression hold key while the IMU is connected.
module instrument_keys #(
    parameter CLK_HZ=50000000,parameter DEBOUNCE_TICKS=CLK_HZ/50,parameter ALLOW_TEST=1,parameter ALLOW_MENU=1,parameter ALLOW_LAYOUT=0,parameter LAYOUT_HOLD_TICKS=(CLK_HZ/2)*3
)(
    input clk,input rst_n,input key0_n,key1_n,key2_n,
    input [3:0] note_count, input layout_chord_free,input demo_mode,
    output reg action_press,output expression_hold,output reg sensor_reset,
    output reg layout_cycle,output layout_ready,
    output reg [3:0] demo_zone,output reg menu_open,output reg [2:0] menu_focus,
    output reg [1:0] preset_id,release_id,output reg test_requested,
    output reg [4:0] test_voice,output reg [31:0] mute_mask,
    output reg delay_enabled,output reg [3:0] delay_setting,
    output reg [1:0] feedback_setting,wet_setting
);
    reg [1:0] sync0,sync1,sync2;
    reg [2:0] stable;
    reg [31:0] count0,count1,count2,long_count;
    reg long_sent;
    reg [31:0] menu_hold_count;reg menu_hold_sent,offline_action;
    reg previous_demo_mode;
    reg layout_pending;reg [1:0] layout_free_sync;
    assign layout_ready=layout_pending;
    wire [3:0] bounded_count=(note_count>=1 && note_count<=12) ? note_count : 7;
    wire press0=(sync0[1]!=stable[0]) && count0==DEBOUNCE_TICKS-1 && !sync0[1];
    wire press1=(sync1[1]!=stable[1]) && count1==DEBOUNCE_TICKS-1 && !sync1[1];
    wire press2=(sync2[1]!=stable[2]) && count2==DEBOUNCE_TICKS-1 && !sync2[1];
    wire release0=(sync0[1]!=stable[0]) && count0==DEBOUNCE_TICKS-1 && sync0[1];
    assign expression_hold=!stable[2] && !menu_open && !test_requested;
    always @(posedge clk) begin
        if(!rst_n) begin
            sync0<=3;sync1<=3;sync2<=3;stable<=7;count0<=0;count1<=0;count2<=0;
            long_count<=0;long_sent<=0;action_press<=0;sensor_reset<=0;demo_zone<=3;
            menu_open<=0;menu_focus<=0;preset_id<=0;release_id<=0;
            menu_hold_count<=0;menu_hold_sent<=0;offline_action<=0;
            test_requested<=0;test_voice<=0;mute_mask<=0;
            delay_enabled<=0;delay_setting<=4;feedback_setting<=2;wet_setting<=1;
            previous_demo_mode<=1;layout_cycle<=0;layout_pending<=0;layout_free_sync<=3;
        end else begin
            layout_free_sync<={layout_free_sync[0],layout_chord_free};
            sync0<={sync0[0],key0_n};sync1<={sync1[0],key1_n};sync2<={sync2[0],key2_n};
            action_press<=0;sensor_reset<=0;layout_cycle<=0;previous_demo_mode<=demo_mode;
            if(demo_zone>=bounded_count)demo_zone<=bounded_count>>1;
            if(sync0[1]==stable[0]) count0<=0;
            else if(count0==DEBOUNCE_TICKS-1) begin stable[0]<=sync0[1];count0<=0;end
            else count0<=count0+1'b1;
            if(sync1[1]==stable[1]) count1<=0;
            else if(count1==DEBOUNCE_TICKS-1) begin stable[1]<=sync1[1];count1<=0;end
            else count1<=count1+1'b1;
            if(sync2[1]==stable[2]) count2<=0;
            else if(count2==DEBOUNCE_TICKS-1) begin stable[2]<=sync2[1];count2<=0;end
            else count2<=count2+1'b1;
            if(stable[1] || menu_open || test_requested) begin long_count<=0;long_sent<=0;end
            else if(!long_sent) begin
                if(long_count==(CLK_HZ/2)*3-1) begin sensor_reset<=1;long_sent<=1;end
                else long_count<=long_count+1'b1;
            end
            if(press0) begin offline_action<=1;menu_hold_count<=0;menu_hold_sent<=0;layout_pending<=0;end
            if(ALLOW_LAYOUT && !stable[0] && offline_action && !menu_hold_sent)begin
                if(!layout_free_sync[1])begin menu_hold_sent<=1;layout_pending<=0;end
                else if(menu_hold_count>=LAYOUT_HOLD_TICKS-1)begin layout_pending<=1;menu_hold_sent<=1;end
                else menu_hold_count<=menu_hold_count+1'b1;
            end
            if(ALLOW_MENU && !stable[0] && offline_action && !menu_hold_sent) begin
                if(menu_hold_count==(CLK_HZ/2)*3-1) begin
                    if(test_requested)begin test_requested<=0;menu_open<=0;end
                    else menu_open<=!menu_open;
                    menu_focus<=0;menu_hold_sent<=1;
                end else menu_hold_count<=menu_hold_count+1'b1;
            end
            if(release0) begin
                if(ALLOW_LAYOUT && layout_pending && layout_free_sync[1])layout_cycle<=1;
                layout_pending<=0;
                if(offline_action && !menu_hold_sent) begin
                    if(test_requested)mute_mask[test_voice]<=!mute_mask[test_voice];
                    else if(menu_open)menu_focus<=menu_focus==6 ? 0 : (!ALLOW_TEST && menu_focus==1) ? 3 : menu_focus+1'b1;
                    else action_press<=1;
                end
                menu_hold_count<=0;menu_hold_sent<=0;offline_action<=0;
            end
            if(test_requested)begin
                if(press1 && sync2[1] && test_voice!=0)test_voice<=test_voice-1'b1;
                else if(press2 && sync1[1] && test_voice!=31)test_voice<=test_voice+1'b1;
            end else if(menu_open) begin
                if(press1 && sync2[1]) begin
                    if(menu_focus==0)preset_id<=preset_id-1'b1;
                    else if(menu_focus==1 && release_id!=0)release_id<=release_id-1'b1;
                    else if(menu_focus==3)delay_enabled<=0;
                    else if(menu_focus==4 && delay_setting!=0)delay_setting<=delay_setting-1'b1;
                    else if(menu_focus==5 && feedback_setting!=0)feedback_setting<=feedback_setting-1'b1;
                    else if(menu_focus==6 && wet_setting!=0)wet_setting<=wet_setting-1'b1;
                end else if(press2 && sync1[1]) begin
                    if(menu_focus==0)preset_id<=preset_id+1'b1;
                    else if(menu_focus==1 && release_id<2)release_id<=release_id+1'b1;
                    else if(menu_focus==2 && ALLOW_TEST)begin
                        test_requested<=1;test_voice<=0;mute_mask<=0;menu_open<=0;
                    end
                    else if(menu_focus==3)delay_enabled<=1;
                    else if(menu_focus==4 && delay_setting<13)delay_setting<=delay_setting+1'b1;
                    else if(menu_focus==5 && feedback_setting<3)feedback_setting<=feedback_setting+1'b1;
                    else if(menu_focus==6 && wet_setting<3)wet_setting<=wet_setting+1'b1;
                end
            end else if(demo_mode) begin
                if(press1 && sync2[1] && demo_zone>0) demo_zone<=demo_zone-1'b1;
                else if(press2 && sync1[1] && demo_zone<bounded_count-1) demo_zone<=demo_zone+1'b1;
            end
            // A mode transition wins even if it coincides with release or the
            // long-press threshold. A held key must be released and pressed anew.
            if(demo_mode!=previous_demo_mode) begin
                menu_open<=0;menu_focus<=0;offline_action<=0;test_requested<=0;
                menu_hold_count<=0;menu_hold_sent<=0;layout_pending<=0;action_press<=0;sensor_reset<=0;
            end
        end
    end
endmodule
