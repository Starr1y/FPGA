// Pin-independent encoder, pedal and two wrist buttons. No board assignments.
// Outputs are one core-clock pulses; the 1ms signal is an enable, never a clock.
module performance_controls #(
 parameter CLK_HZ=50000000,ENC_DEBOUNCE_MS=2,EDGES_PER_STEP=4,
 parameter BUTTON_DEBOUNCE_MS=20,SHORT_MS=50,LONG_MS=1500
)(input clk,rst_n,enabled,input encoder_a,encoder_b,encoder_button_n,pedal_n,
 input[1:0]wrist_button_n,
 output reg encoder_step,encoder_direction,output encoder_short,encoder_long,
 output reg pedal_toggle,output[1:0]wrist_short,wrist_long,
 output[3:0]button_ready,output reg[15:0]invalid_transitions);
 initial begin
  if(CLK_HZ<1000 || CLK_HZ%1000!=0)$fatal(1,"CLK_HZ must be a positive multiple of 1000");
  if(EDGES_PER_STEP!=2 && EDGES_PER_STEP!=4)$fatal(1,"EDGES_PER_STEP must be 2 or 4");
 end
 reg[31:0]divider;wire tick_ms=divider==CLK_HZ/1000-1;
 always @(posedge clk)begin if(!rst_n)divider<=0;else divider<=tick_ms ? 0 : divider+1'b1;end
 reg[1:0]phase1,phase2,phase,candidate;reg[15:0]phase_count;reg initialized;
 reg signed[3:0]partial;
 reg signed[2:0]delta;reg signed[4:0]next_partial;
 always @*begin
  delta=0;
  case({phase,phase2})
   4'b0001,4'b0111,4'b1110,4'b1000:delta=1;
   4'b0010,4'b1011,4'b1101,4'b0100:delta=-1;
   default:delta=0;
  endcase
  next_partial=$signed(partial)+$signed(delta);
 end
 always @(posedge clk)begin
  if(!rst_n)begin phase1<=3;phase2<=3;phase<=3;candidate<=3;phase_count<=0;initialized<=0;partial<=0;encoder_step<=0;encoder_direction<=0;invalid_transitions<=0;end
  else begin
   phase1<={encoder_a,encoder_b};phase2<=phase1;encoder_step<=0;
   if(!enabled)begin initialized<=0;partial<=0;phase_count<=0;phase<=phase2;candidate<=phase2;end
   else if(tick_ms)begin
    if(!initialized)begin
     if(phase2!=phase)begin phase<=phase2;phase_count<=0;end
     else if(phase_count>=ENC_DEBOUNCE_MS-1)begin initialized<=1;phase_count<=0;candidate<=phase;end
     else phase_count<=phase_count+1'b1;
    end else if(phase2==phase)begin phase_count<=0;candidate<=phase;end
    else if(phase2!=candidate)begin candidate<=phase2;phase_count<=1;end
    else if(phase_count>=ENC_DEBOUNCE_MS-1)begin
     phase<=phase2;phase_count<=0;
     if(delta==0)begin partial<=0;if(invalid_transitions!=16'hffff)invalid_transitions<=invalid_transitions+1'b1;end
     else if(next_partial>=EDGES_PER_STEP)begin partial<=0;encoder_step<=1;encoder_direction<=1;end
     else if(next_partial<=-EDGES_PER_STEP)begin partial<=0;encoder_step<=1;encoder_direction<=0;end
     else partial<=next_partial[3:0];
    end else phase_count<=phase_count+1'b1;
   end
  end
 end
 wire pedal_short,pedal_long;wire[3:0]pressed;
 release_button #(.DEBOUNCE_MS(BUTTON_DEBOUNCE_MS),.SHORT_MS(SHORT_MS),.LONG_MS(LONG_MS)) encoder_key(
  .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.enabled(enabled),.button_n(encoder_button_n),
  .short_release(encoder_short),.long_release(encoder_long),.pressed(pressed[0]),.ready(button_ready[0]));
 release_button #(.DEBOUNCE_MS(BUTTON_DEBOUNCE_MS),.SHORT_MS(SHORT_MS),.LONG_MS(LONG_MS)) pedal(
  .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.enabled(enabled),.button_n(pedal_n),
  .short_release(pedal_short),.long_release(pedal_long),.pressed(pressed[1]),.ready(button_ready[1]));
 always @(posedge clk)begin if(!rst_n)pedal_toggle<=0;else pedal_toggle<=enabled && (pedal_short|pedal_long);end
 genvar h;generate for(h=0;h<2;h=h+1)begin:wrist
  release_button #(.DEBOUNCE_MS(BUTTON_DEBOUNCE_MS),.SHORT_MS(SHORT_MS),.LONG_MS(LONG_MS)) key(
   .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.enabled(enabled),.button_n(wrist_button_n[h]),
   .short_release(wrist_short[h]),.long_release(wrist_long[h]),.pressed(pressed[h+2]),.ready(button_ready[h+2]));
 end endgenerate
endmodule
