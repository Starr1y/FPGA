// Local six-axis quaternion complementary filter (not the MPU proprietary DMP).
// Q24 state; one shared 32x32 multiplier. Acceleration feedback is gated near1g.
// Gyro bias requires stationary input; yaw remains relative and may drift.
module mpu6050_fusion #(parameter BIAS_LOG2=8,WARMUP_SAMPLES=600)(
 input clk,rst_n,start,input signed[15:0]ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,
 input[15:0]dt_us,output busy,output reg done,output ready,
 output reg signed[15:0]qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz,
 output reg[31:0]overruns
);
 reg signed[31:0]r[0:31];reg[8:0]pc;reg[1:0]phase;
 reg signed[31:0]ma,mb;reg signed[63:0]product;
 reg signed[31:0]bias[0:2],sum[0:2];reg[BIAS_LOG2:0]bias_count;reg bias_ready;
 reg[15:0]warmup;reg accel_quiet;integer i;
 wire stationary=(gx_raw<328 && gx_raw> -328 && gy_raw<328 && gy_raw> -328 && gz_raw<328 && gz_raw> -328 && accel_quiet);
 assign busy=pc!=0;assign ready=bias_ready && warmup>=WARMUP_SAMPLES;



 reg signed[15:0]gyro_x,gyro_y,gyro_z;


 // One registered operand pair and one writeback port for the microprogram.
 // No frequency/precision change: arithmetic wraps/truncates exactly as v2.8.
 reg [2:0] op_d,op_q;
 reg [4:0] src_a,src_b,dst_d,dst_q;
 reg [5:0] shift_d,shift_q;
 reg feedback_d,write_q;
 reg signed [31:0] sum_q;
 wire subtract_q=op_q==3'd3;
 wire [31:0] add_b=mb ^ {32{subtract_q}};
 always @* begin
  op_d=0;src_a=0;src_b=0;dst_d=0;shift_d=0;feedback_d=0;
  case(pc)
   9'd1: begin op_d=3'd1;src_a=5'd4;src_b=5'd28;dst_d=5'd4;shift_d=6'd0;feedback_d=1'b0;end
   9'd2: begin op_d=3'd1;src_a=5'd5;src_b=5'd28;dst_d=5'd5;shift_d=6'd0;feedback_d=1'b0;end
   9'd3: begin op_d=3'd1;src_a=5'd6;src_b=5'd28;dst_d=5'd6;shift_d=6'd0;feedback_d=1'b0;end
   9'd5: begin op_d=3'd1;src_a=5'd7;src_b=5'd7;dst_d=5'd20;shift_d=6'd24;feedback_d=1'b0;end
   9'd6: begin op_d=3'd1;src_a=5'd8;src_b=5'd8;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd7: begin op_d=3'd2;src_a=5'd20;src_b=5'd22;dst_d=5'd20;shift_d=6'd0;feedback_d=1'b0;end
   9'd8: begin op_d=3'd1;src_a=5'd9;src_b=5'd9;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd9: begin op_d=3'd2;src_a=5'd20;src_b=5'd22;dst_d=5'd20;shift_d=6'd0;feedback_d=1'b0;end
   9'd10: begin op_d=3'd1;src_a=5'd0;src_b=5'd2;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd11: begin op_d=3'd1;src_a=5'd3;src_b=5'd1;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd12: begin op_d=3'd3;src_a=5'd22;src_b=5'd23;dst_d=5'd10;shift_d=6'd0;feedback_d=1'b0;end
   9'd13: begin op_d=3'd2;src_a=5'd10;src_b=5'd10;dst_d=5'd10;shift_d=6'd0;feedback_d=1'b0;end
   9'd14: begin op_d=3'd1;src_a=5'd3;src_b=5'd0;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd15: begin op_d=3'd1;src_a=5'd1;src_b=5'd2;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd16: begin op_d=3'd2;src_a=5'd22;src_b=5'd23;dst_d=5'd11;shift_d=6'd0;feedback_d=1'b0;end
   9'd17: begin op_d=3'd2;src_a=5'd11;src_b=5'd11;dst_d=5'd11;shift_d=6'd0;feedback_d=1'b0;end
   9'd18: begin op_d=3'd1;src_a=5'd0;src_b=5'd0;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd19: begin op_d=3'd1;src_a=5'd1;src_b=5'd1;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd20: begin op_d=3'd2;src_a=5'd22;src_b=5'd23;dst_d=5'd22;shift_d=6'd0;feedback_d=1'b0;end
   9'd21: begin op_d=3'd2;src_a=5'd22;src_b=5'd22;dst_d=5'd22;shift_d=6'd0;feedback_d=1'b0;end
   9'd22: begin op_d=3'd3;src_a=5'd25;src_b=5'd22;dst_d=5'd12;shift_d=6'd0;feedback_d=1'b0;end
   9'd23: begin op_d=3'd1;src_a=5'd8;src_b=5'd12;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd24: begin op_d=3'd1;src_a=5'd9;src_b=5'd11;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd25: begin op_d=3'd3;src_a=5'd22;src_b=5'd23;dst_d=5'd13;shift_d=6'd0;feedback_d=1'b0;end
   9'd26: begin op_d=3'd2;src_a=5'd13;src_b=5'd13;dst_d=5'd13;shift_d=6'd0;feedback_d=1'b0;end
   9'd27: begin op_d=3'd1;src_a=5'd9;src_b=5'd10;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd28: begin op_d=3'd1;src_a=5'd7;src_b=5'd12;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd29: begin op_d=3'd3;src_a=5'd22;src_b=5'd23;dst_d=5'd14;shift_d=6'd0;feedback_d=1'b0;end
   9'd30: begin op_d=3'd2;src_a=5'd14;src_b=5'd14;dst_d=5'd14;shift_d=6'd0;feedback_d=1'b0;end
   9'd31: begin op_d=3'd1;src_a=5'd7;src_b=5'd11;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd32: begin op_d=3'd1;src_a=5'd8;src_b=5'd10;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd33: begin op_d=3'd3;src_a=5'd22;src_b=5'd23;dst_d=5'd15;shift_d=6'd0;feedback_d=1'b0;end
   9'd34: begin op_d=3'd2;src_a=5'd15;src_b=5'd15;dst_d=5'd15;shift_d=6'd0;feedback_d=1'b0;end
   9'd35: begin op_d=3'd2;src_a=5'd4;src_b=5'd13;dst_d=5'd4;shift_d=6'd0;feedback_d=1'b1;end
   9'd36: begin op_d=3'd2;src_a=5'd5;src_b=5'd14;dst_d=5'd5;shift_d=6'd0;feedback_d=1'b1;end
   9'd37: begin op_d=3'd2;src_a=5'd6;src_b=5'd15;dst_d=5'd6;shift_d=6'd0;feedback_d=1'b1;end
   9'd38: begin op_d=3'd1;src_a=5'd3;src_b=5'd4;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd39: begin op_d=3'd1;src_a=5'd1;src_b=5'd6;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd40: begin op_d=3'd1;src_a=5'd2;src_b=5'd5;dst_d=5'd24;shift_d=6'd24;feedback_d=1'b0;end
   9'd41: begin op_d=3'd2;src_a=5'd22;src_b=5'd23;dst_d=5'd16;shift_d=6'd0;feedback_d=1'b0;end
   9'd42: begin op_d=3'd3;src_a=5'd16;src_b=5'd24;dst_d=5'd16;shift_d=6'd0;feedback_d=1'b0;end
   9'd43: begin op_d=3'd1;src_a=5'd16;src_b=5'd30;dst_d=5'd16;shift_d=6'd30;feedback_d=1'b0;end
   9'd44: begin op_d=3'd2;src_a=5'd16;src_b=5'd0;dst_d=5'd16;shift_d=6'd0;feedback_d=1'b0;end
   9'd45: begin op_d=3'd1;src_a=5'd3;src_b=5'd5;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd46: begin op_d=3'd1;src_a=5'd2;src_b=5'd4;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd47: begin op_d=3'd1;src_a=5'd0;src_b=5'd6;dst_d=5'd24;shift_d=6'd24;feedback_d=1'b0;end
   9'd48: begin op_d=3'd2;src_a=5'd22;src_b=5'd23;dst_d=5'd17;shift_d=6'd0;feedback_d=1'b0;end
   9'd49: begin op_d=3'd3;src_a=5'd17;src_b=5'd24;dst_d=5'd17;shift_d=6'd0;feedback_d=1'b0;end
   9'd50: begin op_d=3'd1;src_a=5'd17;src_b=5'd30;dst_d=5'd17;shift_d=6'd30;feedback_d=1'b0;end
   9'd51: begin op_d=3'd2;src_a=5'd17;src_b=5'd1;dst_d=5'd17;shift_d=6'd0;feedback_d=1'b0;end
   9'd52: begin op_d=3'd1;src_a=5'd3;src_b=5'd6;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd53: begin op_d=3'd1;src_a=5'd0;src_b=5'd5;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd54: begin op_d=3'd1;src_a=5'd1;src_b=5'd4;dst_d=5'd24;shift_d=6'd24;feedback_d=1'b0;end
   9'd55: begin op_d=3'd2;src_a=5'd22;src_b=5'd23;dst_d=5'd18;shift_d=6'd0;feedback_d=1'b0;end
   9'd56: begin op_d=3'd3;src_a=5'd18;src_b=5'd24;dst_d=5'd18;shift_d=6'd0;feedback_d=1'b0;end
   9'd57: begin op_d=3'd1;src_a=5'd18;src_b=5'd30;dst_d=5'd18;shift_d=6'd30;feedback_d=1'b0;end
   9'd58: begin op_d=3'd2;src_a=5'd18;src_b=5'd2;dst_d=5'd18;shift_d=6'd0;feedback_d=1'b0;end
   9'd59: begin op_d=3'd1;src_a=5'd0;src_b=5'd4;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd60: begin op_d=3'd1;src_a=5'd1;src_b=5'd5;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd61: begin op_d=3'd1;src_a=5'd2;src_b=5'd6;dst_d=5'd24;shift_d=6'd24;feedback_d=1'b0;end
   9'd62: begin op_d=3'd3;src_a=5'd25;src_b=5'd25;dst_d=5'd19;shift_d=6'd0;feedback_d=1'b0;end
   9'd63: begin op_d=3'd3;src_a=5'd19;src_b=5'd22;dst_d=5'd19;shift_d=6'd0;feedback_d=1'b0;end
   9'd64: begin op_d=3'd3;src_a=5'd19;src_b=5'd23;dst_d=5'd19;shift_d=6'd0;feedback_d=1'b0;end
   9'd65: begin op_d=3'd3;src_a=5'd19;src_b=5'd24;dst_d=5'd19;shift_d=6'd0;feedback_d=1'b0;end
   9'd66: begin op_d=3'd1;src_a=5'd19;src_b=5'd30;dst_d=5'd19;shift_d=6'd30;feedback_d=1'b0;end
   9'd67: begin op_d=3'd2;src_a=5'd19;src_b=5'd3;dst_d=5'd19;shift_d=6'd0;feedback_d=1'b0;end
   9'd68: begin op_d=3'd1;src_a=5'd16;src_b=5'd16;dst_d=5'd20;shift_d=6'd24;feedback_d=1'b0;end
   9'd69: begin op_d=3'd1;src_a=5'd17;src_b=5'd17;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd70: begin op_d=3'd2;src_a=5'd20;src_b=5'd22;dst_d=5'd20;shift_d=6'd0;feedback_d=1'b0;end
   9'd71: begin op_d=3'd1;src_a=5'd18;src_b=5'd18;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd72: begin op_d=3'd2;src_a=5'd20;src_b=5'd22;dst_d=5'd20;shift_d=6'd0;feedback_d=1'b0;end
   9'd73: begin op_d=3'd1;src_a=5'd19;src_b=5'd19;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd74: begin op_d=3'd2;src_a=5'd20;src_b=5'd22;dst_d=5'd20;shift_d=6'd0;feedback_d=1'b0;end
   9'd75: begin op_d=3'd3;src_a=5'd27;src_b=5'd20;dst_d=5'd21;shift_d=6'd0;feedback_d=1'b0;end
   9'd76: begin op_d=3'd4;src_a=5'd21;src_b=5'd21;dst_d=5'd21;shift_d=6'd1;feedback_d=1'b0;end
   9'd77: begin op_d=3'd1;src_a=5'd16;src_b=5'd21;dst_d=5'd0;shift_d=6'd24;feedback_d=1'b0;end
   9'd78: begin op_d=3'd1;src_a=5'd17;src_b=5'd21;dst_d=5'd1;shift_d=6'd24;feedback_d=1'b0;end
   9'd79: begin op_d=3'd1;src_a=5'd18;src_b=5'd21;dst_d=5'd2;shift_d=6'd24;feedback_d=1'b0;end
   9'd80: begin op_d=3'd1;src_a=5'd19;src_b=5'd21;dst_d=5'd3;shift_d=6'd24;feedback_d=1'b0;end
   9'd81: begin op_d=3'd1;src_a=5'd0;src_b=5'd2;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd82: begin op_d=3'd1;src_a=5'd3;src_b=5'd1;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd83: begin op_d=3'd3;src_a=5'd22;src_b=5'd23;dst_d=5'd10;shift_d=6'd0;feedback_d=1'b0;end
   9'd84: begin op_d=3'd2;src_a=5'd10;src_b=5'd10;dst_d=5'd10;shift_d=6'd0;feedback_d=1'b0;end
   9'd85: begin op_d=3'd1;src_a=5'd3;src_b=5'd0;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd86: begin op_d=3'd1;src_a=5'd1;src_b=5'd2;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd87: begin op_d=3'd2;src_a=5'd22;src_b=5'd23;dst_d=5'd11;shift_d=6'd0;feedback_d=1'b0;end
   9'd88: begin op_d=3'd2;src_a=5'd11;src_b=5'd11;dst_d=5'd11;shift_d=6'd0;feedback_d=1'b0;end
   9'd89: begin op_d=3'd1;src_a=5'd0;src_b=5'd0;dst_d=5'd22;shift_d=6'd24;feedback_d=1'b0;end
   9'd90: begin op_d=3'd1;src_a=5'd1;src_b=5'd1;dst_d=5'd23;shift_d=6'd24;feedback_d=1'b0;end
   9'd91: begin op_d=3'd2;src_a=5'd22;src_b=5'd23;dst_d=5'd22;shift_d=6'd0;feedback_d=1'b0;end
   9'd92: begin op_d=3'd2;src_a=5'd22;src_b=5'd22;dst_d=5'd22;shift_d=6'd0;feedback_d=1'b0;end
   9'd93: begin op_d=3'd3;src_a=5'd25;src_b=5'd22;dst_d=5'd12;shift_d=6'd0;feedback_d=1'b0;end
   9'd94: begin op_d=3'd1;src_a=5'd10;src_b=5'd29;dst_d=5'd10;shift_d=6'd24;feedback_d=1'b0;end
   9'd95: begin op_d=3'd1;src_a=5'd7;src_b=5'd29;dst_d=5'd7;shift_d=6'd24;feedback_d=1'b0;end
   9'd96: begin op_d=3'd1;src_a=5'd11;src_b=5'd29;dst_d=5'd11;shift_d=6'd24;feedback_d=1'b0;end
   9'd97: begin op_d=3'd1;src_a=5'd8;src_b=5'd29;dst_d=5'd8;shift_d=6'd24;feedback_d=1'b0;end
   9'd98: begin op_d=3'd1;src_a=5'd12;src_b=5'd29;dst_d=5'd12;shift_d=6'd24;feedback_d=1'b0;end
   9'd99: begin op_d=3'd1;src_a=5'd9;src_b=5'd29;dst_d=5'd9;shift_d=6'd24;feedback_d=1'b0;end
   default:begin end
  endcase
 end

 always @(posedge clk)product<=ma*mb;
 always @(posedge clk)begin
  if(!rst_n)begin
   qx<=0;qy<=0;qz<=0;qw<=16384;ax<=0;ay<=0;az<=0;gx<=0;gy<=0;gz<=0;gravity_x<=0;gravity_y<=0;gravity_z<=0;lx<=0;ly<=0;lz<=0;
   op_q<=0;dst_q<=0;shift_q<=0;write_q<=0;sum_q<=0;pc<=0;phase<=0;done<=0;accel_quiet<=0;ma<=0;mb<=0;bias_count<=0;bias_ready<=0;warmup<=0;overruns<=0;gyro_x<=0;gyro_y<=0;gyro_z<=0;
   for(i=0;i<32;i=i+1)r[i]<=0;
   r[3]<=16777216;r[25]<=16777216;r[26]<=33554432;r[27]<=50331648;r[28]<=8927;r[29]<=2511;r[31]<=537;
   for(i=0;i<3;i=i+1)begin bias[i]<=0;sum[i]<=0;end
  end else begin
   done<=0;
   if(pc==10 && phase==0)accel_quiet<=r[20]>10737418 && r[20]<24159191;
   if(start && busy)overruns<=overruns+1'b1;
   if(pc==0 && start)begin
    r[4]<=$signed(gx_raw)-bias[0];r[5]<=$signed(gy_raw)-bias[1];r[6]<=$signed(gz_raw)-bias[2];
    r[7]<=$signed(ax_raw)*32'sd4096;r[8]<=$signed(ay_raw)*32'sd4096;r[9]<=$signed(az_raw)*32'sd4096;
    // dt/2 in Q30; clamp is an admission bound, long outages reset the host.
    r[30]<=(dt_us<1000 ? 16'd1000 : dt_us>10000 ? 16'd10000 : dt_us)*32'd537;
    if(warmup==0 && az_raw<0)begin r[0]<=16777216;r[1]<=0;r[2]<=0;r[3]<=0;end
    pc<=1;phase<=0;
    if(warmup<WARMUP_SAMPLES)warmup<=warmup+1'b1;
    if(!bias_ready)begin
     if(stationary)begin
      if(bias_count==(1<<BIAS_LOG2)-1)begin
       bias[0]<=($signed(sum[0])+$signed(gx_raw))>>>BIAS_LOG2;
       bias[1]<=($signed(sum[1])+$signed(gy_raw))>>>BIAS_LOG2;
       bias[2]<=($signed(sum[2])+$signed(gz_raw))>>>BIAS_LOG2;bias_ready<=1;
      end else begin sum[0]<=sum[0]+$signed(gx_raw);sum[1]<=sum[1]+$signed(gy_raw);sum[2]<=sum[2]+$signed(gz_raw);bias_count<=bias_count+1'b1;end
     end else begin bias_count<=0;sum[0]<=0;sum[1]<=0;sum[2]<=0;end
    end
   end else if(op_d!=0)begin
    case(phase)
     0:begin
      ma<=r[src_a];mb<=r[src_b];op_q<=op_d;dst_q<=dst_d;shift_q<=shift_d;
      write_q<=!feedback_d || (r[20]>10737418 && r[20]<24159191);
      phase<=1;
     end
     1:begin sum_q<=ma+add_b+subtract_q;phase<=2;end
     2:begin
      if(write_q)begin
       if(op_q==1)begin
        case(shift_q)
         24:r[dst_q]<=product>>>24;
         30:r[dst_q]<=product>>>30;
         default:r[dst_q]<=product;
        endcase
       end else if(op_q==4)r[dst_q]<=ma>>>1;
       else r[dst_q]<=sum_q;
      end
      phase<=0;pc<=pc+1'b1;
     end
     default:phase<=0;
    endcase
   end else case(pc)
    4: begin gyro_x<=r[4]>>>15;gyro_y<=r[5]>>>15;gyro_z<=r[6]>>>15;pc<=pc+1'b1;end // GYRO
    100:begin
     qx<=r[0]>>>10;qy<=r[1]>>>10;qz<=r[2]>>>10;qw<=r[3]>>>10;
     ax<=r[7];ay<=r[8];az<=r[9];gravity_x<=r[10];gravity_y<=r[11];gravity_z<=r[12];
     lx<=r[7]-r[10];ly<=r[8]-r[11];lz<=r[9]-r[12];gx<=gyro_x;gy<=gyro_y;gz<=gyro_z;
     done<=1;pc<=0;end
    default:pc<=0;
   endcase
  end
 end
endmodule
