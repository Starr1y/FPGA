// Stereo 24-bit delay arithmetic, 48 kHz. The current instrument input has
// 16-bit precision; this module does not claim a 24-bit oscillator or DAC.
// Two 32768-word ring buffers cover the taskbook's 60..450 ms (2880..21600).
// Synchronous RAM reads and writes; reset only invalidates history, never
// resets every RAM word. Feedback <=3/4, rounded toward zero before storage.
// Wet gain ramps by 32/32768 per sample; dry is retained (wet <=3/4).
// Time changes first fade wet to zero, apply the new tap, then fade back up.
module audio_delay #(parameter DEPTH=32768,parameter ADDR_BITS=$clog2(DEPTH))(
 input clk,input rst_n,input clear,input sample_valid,
 input signed [23:0] input_left,input signed [23:0] input_right,
 input enabled,input [15:0] delay_samples,input [1:0] feedback_setting,wet_setting,
 output reg signed [23:0] output_left,output reg signed [23:0] output_right,
 output reg output_valid,output busy,output [15:0] actual_delay_samples,
 output [15:0] actual_wet_q15,output reg [31:0] clips,overruns,
 output reg [15:0] max_render_cycles
);
 reg signed [23:0] left_memory[0:DEPTH-1],right_memory[0:DEPTH-1];
 reg signed [23:0] read_left,read_right,write_left,write_right;
 reg [ADDR_BITS-1:0] read_address,write_address,pointer;
 reg write_enable;
 always @(posedge clk)begin
  read_left<=left_memory[read_address];read_right<=right_memory[read_address];
  if(write_enable)begin left_memory[write_address]<=write_left;right_memory[write_address]<=write_right;end
 end
 reg [3:0] state;
 reg [15:0] active_delay,wet_gain,wet_for_frame;
 reg [ADDR_BITS:0] history_count;
 reg signed [23:0] dry_left,dry_right,tap_left,tap_right,feedback_left,feedback_right;
 reg signed [24:0] write_sum_left,write_sum_right,difference_left,difference_right;
 reg signed [41:0] product_left,product_right;
 reg signed [31:0] result_left,result_right;
 reg [1:0] frame_feedback;
 reg frame_history_valid;
 reg [15:0] render_cycles;
 wire [15:0] requested_delay=delay_samples<2880 ? 16'd2880 : delay_samples>21600 ? 16'd21600 : delay_samples;
 wire [15:0] target_wet=enabled && requested_delay==active_delay ? {1'b0,wet_setting,13'b0} : 16'd0;
 assign busy=state!=0;
 assign actual_delay_samples=active_delay;
 assign actual_wet_q15=wet_for_frame;
 function signed [23:0] saturate;
  input signed [31:0] value;
  begin
   if(value>8388607)saturate=24'sh7fffff;
   else if(value< -8388608)saturate=24'sh800000;
   else saturate=value[23:0];
  end
 endfunction
 function signed [23:0] feedback_value;
  input signed [23:0] value;input [1:0] setting;
  reg [24:0] magnitude,scaled;
  begin
   magnitude=value<0 ? -$signed({value[23],value}) : {1'b0,value};
   case(setting)
    0:scaled=0;1:scaled=magnitude>>2;2:scaled=magnitude>>1;
    3:scaled=(magnitude+(magnitude<<1))>>2;
   endcase
   feedback_value=value<0 ? -$signed(scaled) : $signed(scaled);
  end
 endfunction
 always @(posedge clk)begin
  if(!rst_n || clear)begin
   state<=0;pointer<=0;read_address<=0;write_address<=0;write_enable<=0;
   history_count<=0;active_delay<=2880;wet_gain<=0;wet_for_frame<=0;
   dry_left<=0;dry_right<=0;tap_left<=0;tap_right<=0;feedback_left<=0;feedback_right<=0;
   write_left<=0;write_right<=0;write_sum_left<=0;write_sum_right<=0;
   difference_left<=0;difference_right<=0;product_left<=0;product_right<=0;
   result_left<=0;result_right<=0;output_left<=0;output_right<=0;output_valid<=0;
   frame_feedback<=0;frame_history_valid<=0;render_cycles<=0;max_render_cycles<=0;clips<=0;overruns<=0;
  end else begin
   output_valid<=0;write_enable<=0;
   if(sample_valid && busy && overruns!=32'hffffffff)overruns<=overruns+1'b1;
   if(busy)render_cycles<=render_cycles+1'b1;
   case(state)
    0:if(sample_valid)begin
     dry_left<=input_left;dry_right<=input_right;
     read_address<=pointer-active_delay;write_address<=pointer;
     frame_history_valid<=history_count>=active_delay;
     frame_feedback<=enabled ? feedback_setting : 2'd0;
     wet_for_frame<=wet_gain;
     if(wet_gain<target_wet)wet_gain<=target_wet-wet_gain<32 ? target_wet : wet_gain+32;
     else if(wet_gain>target_wet)wet_gain<=wet_gain-target_wet<32 ? target_wet : wet_gain-32;
     if(requested_delay!=active_delay && wet_gain==0)active_delay<=requested_delay;
     render_cycles<=0;state<=1;
    end
    1:state<=2; // read_address now reaches synchronous RAM
    2:begin
     tap_left<=frame_history_valid ? read_left : 24'sd0;
     tap_right<=frame_history_valid ? read_right : 24'sd0;state<=3;
    end
    3:begin
     feedback_left<=feedback_value(tap_left,frame_feedback);
     feedback_right<=feedback_value(tap_right,frame_feedback);state<=4;
    end
    4:begin
     write_sum_left<=$signed({dry_left[23],dry_left})+$signed({feedback_left[23],feedback_left});
     write_sum_right<=$signed({dry_right[23],dry_right})+$signed({feedback_right[23],feedback_right});state<=5;
    end
    5:begin
     write_left<=saturate(write_sum_left);write_right<=saturate(write_sum_right);write_enable<=1;
     if(write_sum_left>8388607 || write_sum_left< -8388608 || write_sum_right>8388607 || write_sum_right< -8388608)
      if(clips!=32'hffffffff)clips<=clips+1'b1;
     difference_left<=$signed({tap_left[23],tap_left})-$signed({dry_left[23],dry_left});
     difference_right<=$signed({tap_right[23],tap_right})-$signed({dry_right[23],dry_right});state<=6;
    end
    6:begin
     product_left<=difference_left*$signed({1'b0,wet_for_frame});
     product_right<=difference_right*$signed({1'b0,wet_for_frame});state<=7;
    end
    7:begin
     result_left<=$signed(dry_left)+(product_left>>>15);
     result_right<=$signed(dry_right)+(product_right>>>15);state<=8;
    end
    8:begin
     output_left<=saturate(result_left);output_right<=saturate(result_right);output_valid<=1;
     pointer<=pointer+1'b1;if(history_count<DEPTH)history_count<=history_count+1'b1;
     if(render_cycles+1'b1>max_render_cycles)max_render_cycles<=render_cycles+1'b1;
     state<=0;
    end
   endcase
  end
 end
endmodule
