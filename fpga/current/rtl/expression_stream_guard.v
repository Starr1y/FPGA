// Report cadence admission for the fixed-coefficient expression filter.
// Sensor timestamps are in 100us ticks, independent of packet arrival latency.
module expression_stream_guard #(parameter CLK_HZ=50000000,POSE_HZ=100)(
 input clk,rst_n,clear,enabled,pose_valid,
 input signed [15:0] roll,pitch,
 input [7:0] pose_sequence,input [31:0] pose_timestamp_ticks,
 input pose_timestamp_valid,
 output reg sample_valid,output reg signed [15:0] sample_roll,sample_pitch,
 output reg stream_reset,output reg [15:0] discontinuities
);
 localparam PERIOD=10000/POSE_HZ;
 localparam MIN_DT=PERIOD-PERIOD/20,MAX_DT=PERIOD+PERIOD/20;
 localparam TIMEOUT=CLK_HZ/20>1 ? CLK_HZ/20 : 2;
 localparam TIMER_BITS=$clog2(TIMEOUT+1);
 reg history_valid;reg [7:0] last_sequence;reg [31:0] last_timestamp;
 reg [TIMER_BITS-1:0] silence;
 wire [31:0] dt=pose_timestamp_ticks-last_timestamp;
 wire [7:0] next_sequence=last_sequence+8'd1;
 wire duplicate=pose_sequence==last_sequence && pose_timestamp_ticks==last_timestamp;
 always @(posedge clk) begin
  if(!rst_n)begin
   history_valid<=0;last_sequence<=0;last_timestamp<=0;silence<=0;
   sample_valid<=0;sample_roll<=0;sample_pitch<=0;stream_reset<=1;discontinuities<=0;
  end else begin
   sample_valid<=0;stream_reset<=0;
   if(clear || !enabled)begin history_valid<=0;silence<=0;stream_reset<=1;end
   else if(pose_valid)begin
    silence<=0;
    if(!pose_timestamp_valid)begin
     history_valid<=0;stream_reset<=1;
     if(discontinuities!=16'hffff)discontinuities<=discontinuities+1'b1;
    end else if(!history_valid)begin
     history_valid<=1;last_sequence<=pose_sequence;last_timestamp<=pose_timestamp_ticks;
     stream_reset<=1;
    end else if(pose_sequence==next_sequence && dt>=MIN_DT && dt<=MAX_DT)begin
     last_sequence<=pose_sequence;last_timestamp<=pose_timestamp_ticks;
     sample_roll<=roll;sample_pitch<=pitch;sample_valid<=1;
    end else begin
     stream_reset<=1;
     // Keep the last genuine timestamp on a replay, so the next report can recover.
     if(!duplicate)begin last_sequence<=pose_sequence;last_timestamp<=pose_timestamp_ticks;end
     if(discontinuities!=16'hffff)discontinuities<=discontinuities+1'b1;
    end
   end else if(history_valid)begin
    if(silence==TIMEOUT-1)begin
     history_valid<=0;stream_reset<=1;
     if(discontinuities!=16'hffff)discontinuities<=discontinuities+1'b1;
    end else silence<=silence+1'b1;
   end
  end
 end
endmodule
