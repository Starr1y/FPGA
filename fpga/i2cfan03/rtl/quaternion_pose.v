// q_rel = conjugate(q_origin) * q_sensor. All quaternions are signed Q14.
// Calibration waits 18 stable reports then averages 32 sign-aligned samples:
// 50 reports at 100Hz take about 500ms. Quality/motion are reported;
// Allow light hand tremor and up to two isolated moving reports without
// discarding the accumulated mean. Sustained movement still restarts it.
// Each request has a bounded 10s deadline and requires accuracy >=2.
module quaternion_pose #(parameter CLK_HZ=50000000, parameter CAL_TIMEOUT_TICKS=CLK_HZ*10,
    parameter CAL_GYRO_LIMIT=205,parameter CAL_COMPONENT_LIMIT=768,
    parameter CAL_MOTION_GRACE=2)(
    input clk,input rst_n,input sensor_restarted,input online,input calibrate,
    input quat_valid,input signed [15:0] qx,qy,qz,qw,input [1:0] accuracy,
    input signed [15:0] gx,gy,gz,
    output reg calibrated,output reg calibrating,output reg pose_valid,
    output reg signed [15:0] yaw,pitch,roll,
    // 0: collecting/idle, 1: low accuracy, 2: movement, 3: timed out.
    output reg [1:0] calibration_state,
    output reg [5:0] calibration_progress,output reg [31:0] overruns
);
    reg signed [15:0] origin[0:3],anchor[0:3],current[0:3],relative_q[0:3];
    reg signed [31:0] average[0:3];
    reg [31:0] stable_ticks,calibration_ticks;
    reg [1:0] motion_bad_count;
    reg [3:0] state,index;
    reg signed [15:0] ma,mb;
    reg subtract_term;
    reg signed [31:0] product,matrix_product[0:9];
    reg signed [34:0] sum;
    reg signed [31:0] yaw_x,yaw_y,roll_x,roll_y,pitch_y;
    reg [31:0] pitch_square;
    reg [15:0] pitch_x;
    reg signed [15:0] next_yaw,next_roll;
    reg atan_start,sqrt_start;
    reg signed [31:0] atan_x,atan_y;
    wire atan_busy,atan_valid,sqrt_busy,sqrt_valid;
    wire signed [15:0] atan_angle;
    wire [15:0] sqrt_result;
    integer i;
    wire signed [31:0] d0=$signed(anchor[0])*$signed(qx);
    wire signed [31:0] d1=$signed(anchor[1])*$signed(qy);
    wire signed [31:0] d2=$signed(anchor[2])*$signed(qz);
    wire signed [31:0] d3=$signed(anchor[3])*$signed(qw);
    wire signed [34:0] dot=$signed(d0)+$signed(d1)+$signed(d2)+$signed(d3);
    wire flip=dot<0;
    wire signed [15:0] aligned_x=flip ? -qx : qx;
    wire signed [15:0] aligned_y=flip ? -qy : qy;
    wire signed [15:0] aligned_z=flip ? -qz : qz;
    wire signed [15:0] aligned_w=flip ? -qw : qw;
    function stable_component;
        input signed [15:0] a,b;
        reg signed [16:0] difference;
        begin difference=$signed(a)-$signed(b);stable_component=difference>-CAL_COMPONENT_LIMIT && difference<CAL_COMPONENT_LIMIT;end
    endfunction
    wire steady=gx>-CAL_GYRO_LIMIT && gx<CAL_GYRO_LIMIT && gy>-CAL_GYRO_LIMIT && gy<CAL_GYRO_LIMIT && gz>-CAL_GYRO_LIMIT && gz<CAL_GYRO_LIMIT &&
                (calibration_progress==0 || (stable_component(aligned_x,anchor[0]) &&
                 stable_component(aligned_y,anchor[1]) && stable_component(aligned_z,anchor[2]) &&
                 stable_component(aligned_w,anchor[3])));
    pose_atan2 atan(.clk(clk),.rst_n(rst_n),.start(atan_start),.vx(atan_x),.vy(atan_y),
                     .busy(atan_busy),.valid(atan_valid),.angle(atan_angle));
    pose_isqrt sqrt(.clk(clk),.rst_n(rst_n),.start(sqrt_start),.radicand(pitch_square),
                     .busy(sqrt_busy),.valid(sqrt_valid),.result(sqrt_result));
    always @* begin
        ma=0;mb=0;subtract_term=0;
        if(state==1) begin
            case(index)
                0:begin ma=origin[3];mb=current[0];end
                1:begin ma=origin[0];mb=current[3];subtract_term=1;end
                2:begin ma=origin[1];mb=current[2];subtract_term=1;end
                3:begin ma=origin[2];mb=current[1];end
                4:begin ma=origin[3];mb=current[1];end
                5:begin ma=origin[0];mb=current[2];end
                6:begin ma=origin[1];mb=current[3];subtract_term=1;end
                7:begin ma=origin[2];mb=current[0];subtract_term=1;end
                8:begin ma=origin[3];mb=current[2];end
                9:begin ma=origin[0];mb=current[1];subtract_term=1;end
                10:begin ma=origin[1];mb=current[0];end
                11:begin ma=origin[2];mb=current[3];subtract_term=1;end
                12:begin ma=origin[3];mb=current[3];end
                13:begin ma=origin[0];mb=current[0];end
                14:begin ma=origin[1];mb=current[1];end
                15:begin ma=origin[2];mb=current[2];end
            endcase
        end else if(state==3) begin
            case(index)
                0,1,2,3:begin ma=relative_q[index];mb=relative_q[index];end
                4:begin ma=relative_q[0];mb=relative_q[1];end
                5:begin ma=relative_q[3];mb=relative_q[2];end
                6:begin ma=relative_q[3];mb=relative_q[0];end
                7:begin ma=relative_q[1];mb=relative_q[2];end
                8:begin ma=relative_q[3];mb=relative_q[1];end
                9:begin ma=relative_q[2];mb=relative_q[0];end
            endcase
        end
    end
    wire signed [34:0] accumulated=sum+$signed(product);
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=0;index<=0;product<=0;sum<=0;
            yaw<=0;pitch<=0;roll<=0;pose_valid<=0;calibrated<=0;calibrating<=0;
            calibration_progress<=0;stable_ticks<=0;calibration_ticks<=0;motion_bad_count<=0;calibration_state<=0;overruns<=0;atan_start<=0;sqrt_start<=0;
            atan_x<=0;atan_y<=0;pitch_square<=0;pitch_x<=0;
            yaw_x<=0;yaw_y<=0;roll_x<=0;roll_y<=0;pitch_y<=0;next_yaw<=0;next_roll<=0;
            for(i=0;i<4;i=i+1) begin
                origin[i]<=i==3 ? 16384 : 0;anchor[i]<=0;current[i]<=0;relative_q[i]<=0;average[i]<=0;
            end
            for(i=0;i<10;i=i+1) matrix_product[i]<=0;
        end else begin
            pose_valid<=0;atan_start<=0;sqrt_start<=0;
            if(sqrt_valid) pitch_x<=sqrt_result;
            if(calibrating) begin
                if(calibration_ticks<CAL_TIMEOUT_TICKS) calibration_ticks<=calibration_ticks+1'b1;
            end else calibration_ticks<=0;
            if(calibrating && online && calibration_progress!=0) begin
                if(stable_ticks<CLK_HZ) stable_ticks<=stable_ticks+1'b1;
            end else stable_ticks<=0;
            if(calibrate && online) begin
                calibrated<=0;calibrating<=1;calibration_progress<=0;stable_ticks<=0;calibration_ticks<=0;motion_bad_count<=0;
                calibration_state<=accuracy<2 ? 1 : 0;
                for(i=0;i<4;i=i+1) average[i]<=0;
            end else if(calibrating && calibration_ticks>=CAL_TIMEOUT_TICKS-1) begin
                calibrated<=0;calibrating<=0;calibration_progress<=0;stable_ticks<=0;motion_bad_count<=0;calibration_state<=3;
                for(i=0;i<4;i=i+1) average[i]<=0;
            end else if(calibrating && !online) begin
                calibration_progress<=0;stable_ticks<=0;motion_bad_count<=0;
                for(i=0;i<4;i=i+1) average[i]<=0;
            end else if(quat_valid && calibrating) begin
                if(!online || accuracy<2) begin
                    calibration_state<=1;
                    calibration_progress<=0;stable_ticks<=0;motion_bad_count<=0;
                    for(i=0;i<4;i=i+1) average[i]<=0;
                end else if(!steady) begin
                    calibration_state<=2;
                    // Pause on a transient: do NOT add a moving sample to the mean.
                    if(motion_bad_count<CAL_MOTION_GRACE)motion_bad_count<=motion_bad_count+1'b1;
                    else begin
                        calibration_progress<=0;stable_ticks<=0;motion_bad_count<=0;
                        for(i=0;i<4;i=i+1) average[i]<=0;
                    end
                end else begin
                    calibration_state<=0;motion_bad_count<=0;
                    if(calibration_progress==0) begin anchor[0]<=qx;anchor[1]<=qy;anchor[2]<=qz;anchor[3]<=qw;end
                    if(calibration_progress>=18 && calibration_progress<49) begin
                        average[0]<=average[0]+aligned_x;average[1]<=average[1]+aligned_y;
                        average[2]<=average[2]+aligned_z;average[3]<=average[3]+aligned_w;
                    end
                    // Count alone is insufficient: UART may deliver a burst
                    // of queued reports. Require >=200ms of stable wall time.
                    if(calibration_progress==49 && stable_ticks>=CLK_HZ/5) begin
                        origin[0]<=(average[0]+aligned_x)>>>5;origin[1]<=(average[1]+aligned_y)>>>5;
                        origin[2]<=(average[2]+aligned_z)>>>5;origin[3]<=(average[3]+aligned_w)>>>5;
                        calibrated<=1;calibrating<=0;calibration_progress<=50;
                    end else if(calibration_progress<49) calibration_progress<=calibration_progress+1'b1;
                end
            end
            case(state)
                // The final calibration sample belongs to the old origin.
                // Wait for the next report before publishing a relative pose.
                0:if(quat_valid && !calibrating && !calibrate) begin
                    current[0]<=qx;current[1]<=qy;current[2]<=qz;current[3]<=qw;
                    index<=0;sum<=0;state<=1;
                end
                1:begin product<=subtract_term ? -(ma*mb) : ma*mb;state<=2;end
                2:begin
                    if(index[1:0]==3) begin relative_q[index[3:2]]<=accumulated>>>14;sum<=0;end
                    else sum<=accumulated;
                    if(index==15) begin index<=0;state<=3;end
                    else begin index<=index+1'b1;state<=1;end
                end
                3:begin product<=ma*mb;state<=4;end
                4:begin
                    matrix_product[index]<=product;
                    if(index==9) state<=5;
                    else begin index<=index+1'b1;state<=3;end
                end
                5:begin
                    yaw_x<=($signed(matrix_product[3])+$signed(matrix_product[0])-
                            $signed(matrix_product[1])-$signed(matrix_product[2]))>>>14;
                    yaw_y<=($signed(matrix_product[5])+$signed(matrix_product[4]))>>>13;
                    roll_x<=($signed(matrix_product[3])-$signed(matrix_product[0])-
                             $signed(matrix_product[1])+$signed(matrix_product[2]))>>>14;
                    roll_y<=($signed(matrix_product[6])+$signed(matrix_product[7]))>>>13;
                    pitch_y<=($signed(matrix_product[8])-$signed(matrix_product[9]))>>>13;
                    state<=6;
                end
                6:begin
                    atan_x<=yaw_x;atan_y<=yaw_y;atan_start<=1;
                    pitch_square<=yaw_x*yaw_x+yaw_y*yaw_y;sqrt_start<=1;state<=7;
                end
                7:if(atan_valid) begin next_yaw<=atan_angle;state<=8;end
                8:begin atan_x<=roll_x;atan_y<=roll_y;atan_start<=1;state<=9;end
                9:if(atan_valid) begin next_roll<=atan_angle;state<=10;end
                10:begin atan_x<={16'b0,pitch_x};atan_y<=pitch_y;atan_start<=1;state<=11;end
                11:if(atan_valid) begin yaw<=next_yaw;roll<=next_roll;pitch<=atan_angle;pose_valid<=1;state<=0;end
                default:state<=0;
            endcase
            if(quat_valid && state!=0 && !calibrating && !calibrate) overruns<=overruns+1'b1;
            if(calibrate && online) begin state<=0;pose_valid<=0;atan_start<=0;sqrt_start<=0;end
            if(sensor_restarted) begin
                calibrated<=0;calibrating<=0;calibration_progress<=0;stable_ticks<=0;calibration_ticks<=0;motion_bad_count<=0;calibration_state<=0;state<=0;pose_valid<=0;
                for(i=0;i<4;i=i+1) origin[i]<=i==3 ? 16384 : 0;
            end
        end
    end
endmodule
