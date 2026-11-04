// Local six-axis quaternion complementary filter (not the MPU proprietary DMP).
// Q24 state; one shared 32x32 multiplier. Acceleration feedback is gated near1g.
// Gyro bias requires stationary input; yaw remains relative and may drift.
module mpu6050_fusion_reference #(parameter BIAS_LOG2=8,WARMUP_SAMPLES=600)(
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

 always @(posedge clk)product<=ma*mb;
 always @(posedge clk)begin
  if(!rst_n)begin
   qx<=0;qy<=0;qz<=0;qw<=16384;ax<=0;ay<=0;az<=0;gx<=0;gy<=0;gz<=0;gravity_x<=0;gravity_y<=0;gravity_z<=0;lx<=0;ly<=0;lz<=0;
   pc<=0;phase<=0;done<=0;accel_quiet<=0;ma<=0;mb<=0;bias_count<=0;bias_ready<=0;warmup<=0;overruns<=0;gyro_x<=0;gyro_y<=0;gyro_z<=0;
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
   end else case(pc)
    1: if(phase==0)begin ma<=r[4];mb<=r[28];phase<=1;end else if(phase==1)phase<=2;else begin r[4]<=product>>>0;phase<=0;pc<=pc+1'b1;end // MUL
    2: if(phase==0)begin ma<=r[5];mb<=r[28];phase<=1;end else if(phase==1)phase<=2;else begin r[5]<=product>>>0;phase<=0;pc<=pc+1'b1;end // MUL
    3: if(phase==0)begin ma<=r[6];mb<=r[28];phase<=1;end else if(phase==1)phase<=2;else begin r[6]<=product>>>0;phase<=0;pc<=pc+1'b1;end // MUL
    4: begin gyro_x<=r[4]>>>15;gyro_y<=r[5]>>>15;gyro_z<=r[6]>>>15;pc<=pc+1'b1;end // GYRO
    5: if(phase==0)begin ma<=r[7];mb<=r[7];phase<=1;end else if(phase==1)phase<=2;else begin r[20]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    6: if(phase==0)begin ma<=r[8];mb<=r[8];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    7: begin r[20]<=r[20]+r[22];pc<=pc+1'b1;end // ADD
    8: if(phase==0)begin ma<=r[9];mb<=r[9];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    9: begin r[20]<=r[20]+r[22];pc<=pc+1'b1;end // ADD
    10: if(phase==0)begin ma<=r[0];mb<=r[2];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    11: if(phase==0)begin ma<=r[3];mb<=r[1];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    12: begin r[10]<=r[22]-r[23];pc<=pc+1'b1;end // SUB
    13: begin r[10]<=r[10]+r[10];pc<=pc+1'b1;end // ADD
    14: if(phase==0)begin ma<=r[3];mb<=r[0];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    15: if(phase==0)begin ma<=r[1];mb<=r[2];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    16: begin r[11]<=r[22]+r[23];pc<=pc+1'b1;end // ADD
    17: begin r[11]<=r[11]+r[11];pc<=pc+1'b1;end // ADD
    18: if(phase==0)begin ma<=r[0];mb<=r[0];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    19: if(phase==0)begin ma<=r[1];mb<=r[1];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    20: begin r[22]<=r[22]+r[23];pc<=pc+1'b1;end // ADD
    21: begin r[22]<=r[22]+r[22];pc<=pc+1'b1;end // ADD
    22: begin r[12]<=r[25]-r[22];pc<=pc+1'b1;end // SUB
    23: if(phase==0)begin ma<=r[8];mb<=r[12];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    24: if(phase==0)begin ma<=r[9];mb<=r[11];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    25: begin r[13]<=r[22]-r[23];pc<=pc+1'b1;end // SUB
    26: begin r[13]<=r[13]+r[13];pc<=pc+1'b1;end // ADD
    27: if(phase==0)begin ma<=r[9];mb<=r[10];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    28: if(phase==0)begin ma<=r[7];mb<=r[12];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    29: begin r[14]<=r[22]-r[23];pc<=pc+1'b1;end // SUB
    30: begin r[14]<=r[14]+r[14];pc<=pc+1'b1;end // ADD
    31: if(phase==0)begin ma<=r[7];mb<=r[11];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    32: if(phase==0)begin ma<=r[8];mb<=r[10];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    33: begin r[15]<=r[22]-r[23];pc<=pc+1'b1;end // SUB
    34: begin r[15]<=r[15]+r[15];pc<=pc+1'b1;end // ADD
    35: begin if(r[20]>10737418 && r[20]<24159191)r[4]<=r[4]+r[13];pc<=pc+1'b1;end // FB
    36: begin if(r[20]>10737418 && r[20]<24159191)r[5]<=r[5]+r[14];pc<=pc+1'b1;end // FB
    37: begin if(r[20]>10737418 && r[20]<24159191)r[6]<=r[6]+r[15];pc<=pc+1'b1;end // FB
    38: if(phase==0)begin ma<=r[3];mb<=r[4];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    39: if(phase==0)begin ma<=r[1];mb<=r[6];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    40: if(phase==0)begin ma<=r[2];mb<=r[5];phase<=1;end else if(phase==1)phase<=2;else begin r[24]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    41: begin r[16]<=r[22]+r[23];pc<=pc+1'b1;end // ADD
    42: begin r[16]<=r[16]-r[24];pc<=pc+1'b1;end // SUB
    43: if(phase==0)begin ma<=r[16];mb<=r[30];phase<=1;end else if(phase==1)phase<=2;else begin r[16]<=product>>>30;phase<=0;pc<=pc+1'b1;end // MUL
    44: begin r[16]<=r[16]+r[0];pc<=pc+1'b1;end // ADD
    45: if(phase==0)begin ma<=r[3];mb<=r[5];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    46: if(phase==0)begin ma<=r[2];mb<=r[4];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    47: if(phase==0)begin ma<=r[0];mb<=r[6];phase<=1;end else if(phase==1)phase<=2;else begin r[24]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    48: begin r[17]<=r[22]+r[23];pc<=pc+1'b1;end // ADD
    49: begin r[17]<=r[17]-r[24];pc<=pc+1'b1;end // SUB
    50: if(phase==0)begin ma<=r[17];mb<=r[30];phase<=1;end else if(phase==1)phase<=2;else begin r[17]<=product>>>30;phase<=0;pc<=pc+1'b1;end // MUL
    51: begin r[17]<=r[17]+r[1];pc<=pc+1'b1;end // ADD
    52: if(phase==0)begin ma<=r[3];mb<=r[6];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    53: if(phase==0)begin ma<=r[0];mb<=r[5];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    54: if(phase==0)begin ma<=r[1];mb<=r[4];phase<=1;end else if(phase==1)phase<=2;else begin r[24]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    55: begin r[18]<=r[22]+r[23];pc<=pc+1'b1;end // ADD
    56: begin r[18]<=r[18]-r[24];pc<=pc+1'b1;end // SUB
    57: if(phase==0)begin ma<=r[18];mb<=r[30];phase<=1;end else if(phase==1)phase<=2;else begin r[18]<=product>>>30;phase<=0;pc<=pc+1'b1;end // MUL
    58: begin r[18]<=r[18]+r[2];pc<=pc+1'b1;end // ADD
    59: if(phase==0)begin ma<=r[0];mb<=r[4];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    60: if(phase==0)begin ma<=r[1];mb<=r[5];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    61: if(phase==0)begin ma<=r[2];mb<=r[6];phase<=1;end else if(phase==1)phase<=2;else begin r[24]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    62: begin r[19]<=r[25]-r[25];pc<=pc+1'b1;end // SUB
    63: begin r[19]<=r[19]-r[22];pc<=pc+1'b1;end // SUB
    64: begin r[19]<=r[19]-r[23];pc<=pc+1'b1;end // SUB
    65: begin r[19]<=r[19]-r[24];pc<=pc+1'b1;end // SUB
    66: if(phase==0)begin ma<=r[19];mb<=r[30];phase<=1;end else if(phase==1)phase<=2;else begin r[19]<=product>>>30;phase<=0;pc<=pc+1'b1;end // MUL
    67: begin r[19]<=r[19]+r[3];pc<=pc+1'b1;end // ADD
    68: if(phase==0)begin ma<=r[16];mb<=r[16];phase<=1;end else if(phase==1)phase<=2;else begin r[20]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    69: if(phase==0)begin ma<=r[17];mb<=r[17];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    70: begin r[20]<=r[20]+r[22];pc<=pc+1'b1;end // ADD
    71: if(phase==0)begin ma<=r[18];mb<=r[18];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    72: begin r[20]<=r[20]+r[22];pc<=pc+1'b1;end // ADD
    73: if(phase==0)begin ma<=r[19];mb<=r[19];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    74: begin r[20]<=r[20]+r[22];pc<=pc+1'b1;end // ADD
    75: begin r[21]<=r[27]-r[20];pc<=pc+1'b1;end // SUB
    76: begin r[21]<=$signed(r[21])>>>1;pc<=pc+1'b1;end // SHR
    77: if(phase==0)begin ma<=r[16];mb<=r[21];phase<=1;end else if(phase==1)phase<=2;else begin r[0]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    78: if(phase==0)begin ma<=r[17];mb<=r[21];phase<=1;end else if(phase==1)phase<=2;else begin r[1]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    79: if(phase==0)begin ma<=r[18];mb<=r[21];phase<=1;end else if(phase==1)phase<=2;else begin r[2]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    80: if(phase==0)begin ma<=r[19];mb<=r[21];phase<=1;end else if(phase==1)phase<=2;else begin r[3]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    81: if(phase==0)begin ma<=r[0];mb<=r[2];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    82: if(phase==0)begin ma<=r[3];mb<=r[1];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    83: begin r[10]<=r[22]-r[23];pc<=pc+1'b1;end // SUB
    84: begin r[10]<=r[10]+r[10];pc<=pc+1'b1;end // ADD
    85: if(phase==0)begin ma<=r[3];mb<=r[0];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    86: if(phase==0)begin ma<=r[1];mb<=r[2];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    87: begin r[11]<=r[22]+r[23];pc<=pc+1'b1;end // ADD
    88: begin r[11]<=r[11]+r[11];pc<=pc+1'b1;end // ADD
    89: if(phase==0)begin ma<=r[0];mb<=r[0];phase<=1;end else if(phase==1)phase<=2;else begin r[22]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    90: if(phase==0)begin ma<=r[1];mb<=r[1];phase<=1;end else if(phase==1)phase<=2;else begin r[23]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    91: begin r[22]<=r[22]+r[23];pc<=pc+1'b1;end // ADD
    92: begin r[22]<=r[22]+r[22];pc<=pc+1'b1;end // ADD
    93: begin r[12]<=r[25]-r[22];pc<=pc+1'b1;end // SUB
    94: if(phase==0)begin ma<=r[10];mb<=r[29];phase<=1;end else if(phase==1)phase<=2;else begin r[10]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    95: if(phase==0)begin ma<=r[7];mb<=r[29];phase<=1;end else if(phase==1)phase<=2;else begin r[7]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    96: if(phase==0)begin ma<=r[11];mb<=r[29];phase<=1;end else if(phase==1)phase<=2;else begin r[11]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    97: if(phase==0)begin ma<=r[8];mb<=r[29];phase<=1;end else if(phase==1)phase<=2;else begin r[8]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    98: if(phase==0)begin ma<=r[12];mb<=r[29];phase<=1;end else if(phase==1)phase<=2;else begin r[12]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
    99: if(phase==0)begin ma<=r[9];mb<=r[29];phase<=1;end else if(phase==1)phase<=2;else begin r[9]<=product>>>24;phase<=0;pc<=pc+1'b1;end // MUL
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
