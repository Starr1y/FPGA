// Q24 six-axis orientation. Bias is learned ONLY on explicit reset/center.
// No run-time Z bias adaptation/deadband: slow intentional yaw is preserved.
// Input:8192LSB/g,65.5LSB/(deg/s), timestamps100us. Output signed Q14.
module mpu6050_fusion #(parameter CAL_SAMPLES=400)(
 input clk,rst_n,clear,online,sample_valid,input[31:0]sample_tick,
 input signed[15:0]ax,ay,az,gx,gy,gz,
 output reg ready,valid,output reg signed[15:0]qx,qy,qz,qw,ox,oy,oz,
 output reg[31:0]output_tick,errors,output reg[9:0]calibration_samples
);
 reg[3:0]state;reg[31:0]last_tick,stamp;reg[6:0]dt;reg seen;
 reg signed[39:0]gyro_dt[0:2],accel_dt[0:2];
 reg bias_start;reg[1:0]bias_index;reg[63:0]bias_numerator;
 wire bias_valid,bias_good,bias_busy;wire[63:0]bias_quotient;
 imu_divide64 bias_divider(.clk(clk),.rst_n(rst_n&&!clear&&online),.start(bias_start),.numerator(bias_numerator),.denominator(CAL_SAMPLES),.busy(bias_busy),.valid(bias_valid),.good(bias_good),.quotient(bias_quotient));
 reg signed[63:0]sum[0:2];reg signed[31:0]bias[0:2],rate[0:2],delta[0:2];
 reg signed[15:0]low[0:2],high[0:2];
 reg signed[31:0]q[0:3],n[0:3],a[0:2],gravity[0:2],error[0:2];
 reg initial_start;reg[31:0]initial_norm;
 wire initial_valid,initial_busy;wire[15:0]initial_length;
 pose_isqrt initial_sqrt(.clk(clk),.rst_n(rst_n&&!clear&&online),.start(initial_start),.radicand(initial_norm),.busy(initial_busy),.valid(initial_valid),.result(initial_length));
 reg[31:0]settle;reg use_accel,normal_start;wire normal_valid,normal_good,normal_busy;
 wire[127:0]normal_out;wire[127:0]normal_in={n[3],n[2],n[1],n[0]};
 wire signed[15:0]raw_g[0:2];assign raw_g[0]=gx;assign raw_g[1]=gy;assign raw_g[2]=gz;
 wire signed[63:0]an=$signed(ax)*$signed(ax)+$signed(ay)*$signed(ay)+$signed(az)*$signed(az);
 wire stationary=an>64'd60000000 && an<64'd75000000 && gx>-650 && gx<650 && gy>-650 && gy<650 && gz>-650 && gz<650;
 wire[31:0]elapsed=sample_tick-last_tick;
 function signed[63:0]mul;input signed[31:0]x,y;begin mul=x*y;end endfunction
 function signed[15:0]gyro_q9;input signed[31:0]r;reg signed[63:0]s;begin s=$signed(r)*64'sd8941;gyro_q9=s>>>32;end endfunction
 imu_quaternion_normalize normalizer(.clk(clk),.rst_n(rst_n&&!clear&&online),.start(normal_start),.qin(normal_in),.busy(normal_busy),.valid(normal_valid),.good(normal_good),.qout(normal_out));
 integer i;
 always @(posedge clk)begin
  if(!rst_n || clear || !online)begin
   bias_start<=0;bias_index<=0;bias_numerator<=0;initial_start<=0;initial_norm<=0;state<=0;ready<=0;valid<=0;seen<=0;last_tick<=0;stamp<=0;dt<=0;settle<=0;use_accel<=0;normal_start<=0;qx<=0;qy<=0;qz<=0;qw<=16384;ox<=0;oy<=0;oz<=0;output_tick<=0;errors<=0;calibration_samples<=0;
   for(i=0;i<3;i=i+1)begin gyro_dt[i]<=0;accel_dt[i]<=0;sum[i]<=0;bias[i]<=0;rate[i]<=0;delta[i]<=0;a[i]<=0;gravity[i]<=0;error[i]<=0;low[i]<=32767;high[i]<=-32768;end
   for(i=0;i<4;i=i+1)begin q[i]<=i==3 ? 16777216 : 0;n[i]<=0;end
  end else begin
   valid<=0;normal_start<=0;initial_start<=0;bias_start<=0;
   if(sample_valid && state!=0)errors<=errors+1'b1;
   case(state)
    0:if(sample_valid)begin
     last_tick<=sample_tick;seen<=1;
     if(gx>32000 || gx< -32000 || gy>32000 || gy< -32000 || gz>32000 || gz< -32000)begin ready<=0;calibration_samples<=0;errors<=errors+1'b1;for(i=0;i<3;i=i+1)begin sum[i]<=0;low[i]<=32767;high[i]<=-32768;end end
     else if(calibration_samples<CAL_SAMPLES)begin
      // Consecutive stationary samples with bounded gyro span. No queued burst.
      if(!stationary || (seen && (elapsed<20 || elapsed>100)) ||
         (calibration_samples>4 && (gx>low[0]+40 || gx<high[0]-40 || gy>low[1]+40 || gy<high[1]-40 || gz>low[2]+40 || gz<high[2]-40)))begin
       calibration_samples<=0;for(i=0;i<3;i=i+1)begin sum[i]<=0;low[i]<=32767;high[i]<=-32768;end
      end else begin
       calibration_samples<=calibration_samples+1'b1;
       for(i=0;i<3;i=i+1)begin sum[i]<=sum[i]+raw_g[i];if(raw_g[i]<low[i])low[i]<=raw_g[i];if(raw_g[i]>high[i])high[i]<=raw_g[i];end
       if(calibration_samples==CAL_SAMPLES-1)begin
        // Constant division is calibration-only. Keep fractional raw-count bias.
        // Sum already includes the final sample on the next clock.
        bias_index<=0;
        // Stable two-branch gravity quaternion. Unlike n+az near -1g,
        // the selected large component cannot collapse under sensor noise.
        a[0]<=ax;a[1]<=ay;a[2]<=az;initial_norm<=an[31:0];state<=8;stamp<=sample_tick;
       end
      end
     end else if(elapsed<20 || elapsed>100)begin ready<=0;calibration_samples<=0;errors<=errors+1'b1;for(i=0;i<3;i=i+1)begin sum[i]<=0;low[i]<=32767;high[i]<=-32768;end end
     else begin
      stamp<=sample_tick;dt<=elapsed;
      for(i=0;i<3;i=i+1)rate[i]<=($signed(raw_g[i])*65536)-bias[i];
      a[0]<=$signed(ax)*2048;a[1]<=$signed(ay)*2048;a[2]<=$signed(az)*2048;
      use_accel<=an>64'd54000000 && an<64'd81000000;
      state<=1;
     end
    end
    1:begin
     gravity[0]<=(mul(q[0],q[2])-mul(q[3],q[1]))>>>23;
     gravity[1]<=(mul(q[3],q[0])+mul(q[1],q[2]))>>>23;
     gravity[2]<=16777216-((mul(q[0],q[0])+mul(q[1],q[1]))>>>23);
     ox<=gyro_q9(rate[0]);oy<=gyro_q9(rate[1]);oz<=gyro_q9(rate[2]);state<=2;
    end
    2:begin
     error[0]<=use_accel ? (mul(a[1],gravity[2])-mul(a[2],gravity[1]))>>>24 : 0;
     error[1]<=use_accel ? (mul(a[2],gravity[0])-mul(a[0],gravity[2]))>>>24 : 0;
     error[2]<=use_accel ? (mul(a[0],gravity[1])-mul(a[1],gravity[0]))>>>24 : 0;state<=3;
    end
    3:begin
     for(i=0;i<3;i=i+1)begin gyro_dt[i]<=mul(rate[i],$signed({1'b0,dt}));accel_dt[i]<=mul(error[i],$signed({1'b0,dt}));end
     state<=4;
    end
    4:begin
     for(i=0;i<3;i=i+1)delta[i]<=((gyro_dt[i]*64'sd14649)>>>32)+((accel_dt[i]*64'sd3355)>>>26);
     state<=10;
    end
    10:begin
     n[0]<=q[0]+((mul(q[3],delta[0])+mul(q[1],delta[2])-mul(q[2],delta[1]))>>>24);
     n[1]<=q[1]+((mul(q[3],delta[1])+mul(q[2],delta[0])-mul(q[0],delta[2]))>>>24);
     n[2]<=q[2]+((mul(q[3],delta[2])+mul(q[0],delta[1])-mul(q[1],delta[0]))>>>24);
     n[3]<=q[3]-((mul(q[0],delta[0])+mul(q[1],delta[1])+mul(q[2],delta[2]))>>>24);
     state<=5;
    end
    5:begin normal_start<=1;state<=7;end
    8:begin
     bias_numerator<=sum[bias_index]<0 ? (-sum[bias_index])<<16 : sum[bias_index]<<16;
     bias_start<=1;state<=9;
    end
    9:if(bias_valid)begin
     bias[bias_index]<=sum[bias_index]<0 ? -$signed(bias_quotient[31:0]) : $signed(bias_quotient[31:0]);
     if(bias_index==2)begin initial_start<=1;state<=6;end
     else begin bias_index<=bias_index+1'b1;state<=8;end
    end
    6:if(initial_valid)begin
     if(a[2]>=0)begin n[0]<=a[1]*1024;n[1]<=-a[0]*1024;n[2]<=0;n[3]<=($signed({1'b0,initial_length})+a[2])*1024;end
     else begin n[0]<=($signed({1'b0,initial_length})-a[2])*1024;n[1]<=0;n[2]<=a[0]*1024;n[3]<=a[1]*1024;end
     normal_start<=1;state<=7;
    end
    7:if(normal_valid)begin
     if(!normal_good)begin ready<=0;calibration_samples<=0;errors<=errors+1'b1;for(i=0;i<3;i=i+1)sum[i]<=0;end
     else begin
      for(i=0;i<4;i=i+1)q[i]<=$signed(normal_out[i*32+:32]);
      qx<=$signed(normal_out[0+:32])>>>10;qy<=$signed(normal_out[32+:32])>>>10;qz<=$signed(normal_out[64+:32])>>>10;qw<=$signed(normal_out[96+:32])>>>10;
      ready<=1;valid<=1;output_tick<=stamp;
     end
     state<=0;
    end
    default:state<=0;
   endcase
  end
 end
endmodule

