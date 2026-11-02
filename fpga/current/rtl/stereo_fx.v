// Independent stereo delay, chorus and four-tap feedback reverb.
// One read and one write port per channel; no clearing loop over the RAM.
// An eight-clock transaction fits comfortably between 48kHz samples at 50MHz.
module stereo_fx #(
 parameter ADDR_BITS=14, LFO_INCREMENT=210,
 parameter DEPTH=1<<ADDR_BITS
)(input clk,rst_n,input in_valid,output in_ready,
 input signed[15:0]in_left,in_right,input[1:0]mode,
 input[7:0]wet,feedback,chorus_depth,input[13:0]delay_samples,
 input[1:0]clear_history,
 output reg out_valid,output reg signed[15:0]out_left,out_right,
 output reg[31:0]dropped_samples,clipped_samples);
 reg signed[15:0]memory_left[0:DEPTH-1] /* synthesis syn_ramstyle="block_ram" */;
 reg signed[15:0]memory_right[0:DEPTH-1] /* synthesis syn_ramstyle="block_ram" */;
 reg[2:0]state;
 reg[ADDR_BITS-1:0]write_pointer,primary_left,primary_right;
 reg[ADDR_BITS:0]written_left,written_right;
 reg[7:0]generation_left,generation_right,transaction_left,transaction_right;
 reg[23:0]phase;
 reg signed[15:0]dry_left,dry_right,read_left,read_right;
 reg signed[15:0]tap_left[0:2],tap_right[0:2];
 reg valid_left,valid_right;
 reg[1:0]tx_mode;reg[7:0]tx_wet,tx_feedback,fraction_left,fraction_right;
 reg signed[18:0]echo_left_q,echo_right_q;
 reg signed[15:0]render_left,render_right,store_left,store_right;
 reg[1:0]transaction_clipped;
 assign in_ready=state==0;
 initial if(ADDR_BITS<4 || ADDR_BITS>14)$fatal(1,"ADDR_BITS must be 4..14");
 function[7:0]triangle(input[23:0]p);
  begin triangle=p[23] ? ~p[22:15] : p[22:15];end
 endfunction
 wire signed[17:0]mod_left=($signed({1'b0,triangle(phase)})-18'sd128)*$signed({1'b0,chorus_depth});
 wire signed[17:0]mod_right=($signed({1'b0,triangle(phase+24'h400000)})-18'sd128)*$signed({1'b0,chorus_depth});
 wire signed[17:0]desired_left=$signed({1'b0,delay_samples})+(mod_left>>>7);
 wire signed[17:0]desired_right=$signed({1'b0,delay_samples})+(mod_right>>>7);
 function[ADDR_BITS-1:0]bounded(input signed[17:0]d);
  begin bounded=d<1 ? 1 : d>=DEPTH ? DEPTH-1 : d[ADDR_BITS-1:0];end
 endfunction
 function[ADDR_BITS-1:0]tap_distance(input[ADDR_BITS-1:0]d,input[2:0]stage,input[1:0]kind);
  reg[ADDR_BITS:0]n;
  begin
   n=d;
   if(kind==2 && stage==2)n={1'b0,d}+1'b1;
   else if(kind==3)case(stage)
    2:n=(d>>1)+(d>>2);
    3:n=d>>1;
    4:n=(d>>1)+(d>>2)+(d>>3);
    default:n=d;
   endcase
   tap_distance=n<1 ? 1 : n>=DEPTH ? DEPTH-1 : n[ADDR_BITS-1:0];
  end
 endfunction
 wire[ADDR_BITS-1:0]distance_left=tap_distance(primary_left,state,tx_mode);
 wire[ADDR_BITS-1:0]distance_right=tap_distance(primary_right,state,tx_mode);
 wire[ADDR_BITS-1:0]address_left=write_pointer-distance_left;
 wire[ADDR_BITS-1:0]address_right=write_pointer-distance_right;
 wire left_current=transaction_left==generation_left && !clear_history[0];
 wire right_current=transaction_right==generation_right && !clear_history[1];
 // Synchronous read, separate synchronous write: infer two simple dual-port RAMs.
 // Only the validity counters reset. Unknown/unwritten words never reach output.
 always @(posedge clk)begin
  // Keep RAM read enables low between samples; use enables, not gated clocks.
  if(state>=1 && state<=4)begin
   read_left<=memory_left[address_left];read_right<=memory_right[address_right];
  end
  if(state==7 && rst_n)begin
   memory_left[write_pointer]<=left_current ? store_left : dry_left;
   memory_right[write_pointer]<=right_current ? store_right : dry_right;
  end
 end
 function signed[15:0]saturate(input signed[24:0]v);
  begin saturate=v>32767 ? 16'sh7fff : v< -32768 ? 16'sh8000 : v[15:0];end
 endfunction
 wire signed[15:0]last_left=valid_left ? read_left : 16'sd0;
 wire signed[15:0]last_right=valid_right ? read_right : 16'sd0;
 wire signed[18:0]sum_left=$signed(tap_left[0])+$signed(tap_left[1])+$signed(tap_left[2])+$signed(last_left);
 wire signed[18:0]sum_right=$signed(tap_right[0])+$signed(tap_right[1])+$signed(tap_right[2])+$signed(last_right);
 // Interpolate adjacent chorus taps to avoid one-sample LFO steps.
 wire signed[24:0]chorus_left=($signed(tap_left[0])*$signed({1'b0,(9'd256-{1'b0,fraction_left})})+
  $signed(tap_left[1])*$signed({1'b0,fraction_left}))>>>8;
 wire signed[24:0]chorus_right=($signed(tap_right[0])*$signed({1'b0,(9'd256-{1'b0,fraction_right})})+
  $signed(tap_right[1])*$signed({1'b0,fraction_right}))>>>8;
 wire signed[18:0]echo_left=tx_mode==3 ? sum_left>>>2 : tx_mode==2 ? chorus_left : $signed(tap_left[0]);
 wire signed[18:0]echo_right=tx_mode==3 ? sum_right>>>2 : tx_mode==2 ? chorus_right : $signed(tap_right[0]);
 wire signed[9:0]dry_weight=10'sd256-$signed({1'b0,tx_wet});
 wire signed[24:0]blend_left=($signed(dry_left)*dry_weight+echo_left_q*$signed({1'b0,tx_wet}))>>>8;
 wire signed[24:0]blend_right=($signed(dry_right)*dry_weight+echo_right_q*$signed({1'b0,tx_wet}))>>>8;
 wire signed[24:0]feedback_left=$signed(dry_left)+((echo_left_q*$signed({1'b0,tx_feedback}))>>>8);
 wire signed[24:0]feedback_right=$signed(dry_right)+((echo_right_q*$signed({1'b0,tx_feedback}))>>>8);
 integer k;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;write_pointer<=0;written_left<=0;written_right<=0;
   generation_left<=0;generation_right<=0;transaction_left<=0;transaction_right<=0;
   phase<=0;dry_left<=0;dry_right<=0;primary_left<=1;primary_right<=1;
   valid_left<=0;valid_right<=0;tx_mode<=0;tx_wet<=0;tx_feedback<=0;
   fraction_left<=0;fraction_right<=0;echo_left_q<=0;echo_right_q<=0;
   render_left<=0;render_right<=0;store_left<=0;store_right<=0;transaction_clipped<=0;
   out_valid<=0;out_left<=0;out_right<=0;dropped_samples<=0;clipped_samples<=0;
   for(k=0;k<3;k=k+1)begin tap_left[k]<=0;tap_right[k]<=0;end
  end else begin
   out_valid<=0;
   valid_left<=written_left>=distance_left;valid_right<=written_right>=distance_right;
   if(clear_history[0])begin written_left<=0;generation_left<=generation_left+1'b1;end
   else if(state==7 && written_left<DEPTH-1)written_left<=written_left+1'b1;
   if(clear_history[1])begin written_right<=0;generation_right<=generation_right+1'b1;end
   else if(state==7 && written_right<DEPTH-1)written_right<=written_right+1'b1;
   if(in_valid && !in_ready && dropped_samples!=32'hffffffff)dropped_samples<=dropped_samples+1'b1;
   case(state)
    0:if(in_valid)begin
     dry_left<=in_left;dry_right<=in_right;tx_mode<=mode;tx_wet<=mode==0 ? 0 : wet;
     // Feedback stays below unity; chorus has no recirculating feedback.
     tx_feedback<=mode==1 ? (feedback>192 ? 192 : feedback) : mode==3 ? (feedback>128 ? 128 : feedback) : 0;
     primary_left<=bounded($signed({1'b0,delay_samples})+(mode==2 ? mod_left>>>7 : 18'sd0));
     primary_right<=bounded($signed({1'b0,delay_samples})+(mode==2 ? mod_right>>>7 : 18'sd0));
     fraction_left<=mode!=2 || desired_left<=1 || desired_left>=DEPTH-1 ? 0 : {mod_left[6:0],1'b0};
     fraction_right<=mode!=2 || desired_right<=1 || desired_right>=DEPTH-1 ? 0 : {mod_right[6:0],1'b0};
     transaction_left<=generation_left;transaction_right<=generation_right;state<=1;
    end
    1:state<=2;
    2,3,4:begin
     tap_left[state-2]<=last_left;tap_right[state-2]<=last_right;state<=state+1'b1;
    end
    5:begin echo_left_q<=echo_left;echo_right_q<=echo_right;state<=6;end
    6:begin
     render_left<=saturate(blend_left);render_right<=saturate(blend_right);
     store_left<=saturate(feedback_left);store_right<=saturate(feedback_right);
     transaction_clipped[0]<=blend_left>32767 || blend_left< -32768 || feedback_left>32767 || feedback_left< -32768;
     transaction_clipped[1]<=blend_right>32767 || blend_right< -32768 || feedback_right>32767 || feedback_right< -32768;
     state<=7;
    end
    7:begin
     out_left<=left_current ? render_left : dry_left;out_right<=right_current ? render_right : dry_right;
     out_valid<=1;write_pointer<=write_pointer+1'b1;phase<=phase+LFO_INCREMENT;state<=0;
     if((transaction_clipped[0] && left_current || transaction_clipped[1] && right_current) && clipped_samples!=32'hffffffff)clipped_samples<=clipped_samples+1'b1;
    end
    default:state<=0;
   endcase
  end
 end
endmodule
