// Single-hand performance controller. Angles are degrees*16; acceleration
// and gravity are Q8 m/s^2, gyro is Q9 rad/s. Thresholds need wearer tests.
// FAN04 uses SH-2 0x04 linear acceleration in the sensor body frame.
// Down means local -Z: down = -lz (Q8 m/s^2). No minimum wrist rotation.
// Jerk threshold comparison uses actual 100us sensor timestamps, no divider.
// Negative Z jerk is an independent trigger; current Z acceleration may still be positive.
// A sample gap/restart/origin change invalidates derivative history.
module gesture_control #(
    parameter CLK_HZ=50000000,
    parameter QUIET_TICKS=CLK_HZ/50,
    parameter REFRACTORY_TICKS=CLK_HZ/10,
    parameter STRENGTH_TICKS=CLK_HZ/250,
    parameter HIT_THRESHOLD=640, // 2.5 m/s^2
    parameter JERK_THRESHOLD_Q8=20480, // 80 m/s^3
    parameter MIN_DT_TICKS=20, parameter MAX_DT_TICKS=400,
    parameter QUIET_THRESHOLD=256
)(
    input clk,input rst_n,input sensor_restarted,
    input online,input calibrated,input calibrating,input [1:0] accuracy,
    input [1:0] layout_profile,
    input snapshot_required,snapshot_valid,input[3:0]snapshot_zone,input[1:0]snapshot_octave,snapshot_profile,
    output signed[15:0] filtered_yaw,output[3:0]candidate_zone,
    input pose_valid,input signed [15:0] yaw,pitch,roll,
    input accel_valid,gyro_valid,gravity_valid,
    input linear_valid,input [7:0] linear_sequence,
    input [31:0] linear_timestamp_ticks,input linear_timestamp_valid,
    input signed [15:0] lx,ly,lz,
    input signed [15:0] ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,
    output reg [3:0] selected_zone,output reg out_of_range,output reg drift_warning,
    output data_fresh,output playable,output reg armed,
    output reg note_on,output reg velocity_update,output reg [7:0] velocity,
    output reg [3:0] hit_zone,output reg [1:0] hit_profile,output reg signed [1:0] hit_octave,
    output reg [31:0] hit_count,output reg [7:0] event_id,
    output reg [1:0] last_trigger_reason,output reg signed [15:0] downward_accel,output reg [31:0] processing_overruns
);
    reg [31:0] pose_age,linear_age,gyro_age;
    reg [31:0] quiet_ticks,refractory_ticks,strength_ticks;
    reg [15:0] peak;
    reg strength_active;
    reg sample_event,acceleration_hit,jerk_hit;
    reg have_previous,linear_seen;
    reg [31:0] previous_timestamp;
    reg [7:0] previous_sequence;
    reg signed [16:0] previous_down;
    wire signed [16:0] down_now=-$signed({lz[15],lz});
    wire signed [17:0] jerk_delta=$signed({down_now[16],down_now})-$signed({previous_down[16],previous_down});
    wire [31:0] sample_dt=linear_timestamp_ticks-previous_timestamp;
    wire consecutive=linear_sequence==previous_sequence+8'd1;
    wire interval_ok=sample_dt>=MIN_DT_TICKS && sample_dt<=MAX_DT_TICKS;
    // Explicit widening avoids overflow of the signed delta and products.
    wire signed [47:0] jerk_scaled=$signed({{30{jerk_delta[17]}},jerk_delta})*48'sd10000;
    wire [47:0] jerk_limit={16'd0,sample_dt}*JERK_THRESHOLD_Q8;
    wire jerk_cross=jerk_delta>0 && jerk_scaled>=$signed(jerk_limit);
    reg signed [15:0] previous_yaw,roll_history[0:4];
    reg signed[15:0]yaw_h1,yaw_h2;reg[1:0]yaw_samples;
    wire signed[15:0]smooth_yaw=yaw_samples==2 ? median3(yaw,yaw_h1,yaw_h2) : yaw;
    assign filtered_yaw=smooth_yaw;
    reg have_yaw;reg[3:0]zone_candidate;reg[31:0]zone_since;reg zone_pending;reg[31:0]wall_ticks;
    assign candidate_zone=zone_candidate;
    reg signed [1:0] octave;
    integer i;
    function [15:0] magnitude;
        input signed [15:0] v;
        begin magnitude=v<0 ? -v : v;end
    endfunction
    wire [17:0] gyro_speed={2'b0,magnitude(gx)}+{2'b0,magnitude(gy)}+{2'b0,magnitude(gz)};
    wire signed [16:0] raw_yaw_delta=$signed(yaw)-$signed(previous_yaw);
    wire signed [16:0] yaw_delta=raw_yaw_delta>2880 ? raw_yaw_delta-5760 : raw_yaw_delta< -2880 ? raw_yaw_delta+5760 : raw_yaw_delta;
    // Linear samples must be real and timestamped. 40ms covers report jitter.
    assign data_fresh=pose_age<CLK_HZ/50 && gyro_age<CLK_HZ/50 &&
                      linear_seen && linear_age<CLK_HZ/25;
    wire layout_changed;
    assign playable=online && calibrated && !calibrating && accuracy>=2 && data_fresh &&
                    !out_of_range && !drift_warning && !layout_changed;
    wire quiet=magnitude(downward_accel)<QUIET_THRESHOLD && gyro_speed<102;
    // 180-degree non-cyclic fan. Profile 0=7 natural notes, 1=5 pentatonic, 2=12 semitones.
    function [1:0] normalize_profile;input [1:0] p;
     begin case(p)1:normalize_profile=1;2:normalize_profile=2;default:normalize_profile=0;endcase end
    endfunction
    wire [1:0] profile=normalize_profile(layout_profile);
    wire [3:0] note_count=profile==1 ? 5 : profile==2 ? 12 : 7;
    reg [1:0] previous_profile;
    assign layout_changed=profile!=previous_profile;
    function signed [15:0] zone_cut;
     input [1:0] p;input [3:0] index;
     begin case(p)
      0:case(index)
       0:zone_cut=-1440;
       1:zone_cut=-1029;
       2:zone_cut=-617;
       3:zone_cut=-206;
       4:zone_cut=206;
       5:zone_cut=617;
       6:zone_cut=1029;
       7:zone_cut=1440;
       default:zone_cut=1440;endcase
      1:case(index)
       0:zone_cut=-1440;
       1:zone_cut=-864;
       2:zone_cut=-288;
       3:zone_cut=288;
       4:zone_cut=864;
       5:zone_cut=1440;
       default:zone_cut=1440;endcase
      2:case(index)
       0:zone_cut=-1440;
       1:zone_cut=-1200;
       2:zone_cut=-960;
       3:zone_cut=-720;
       4:zone_cut=-480;
       5:zone_cut=-240;
       6:zone_cut=0;
       7:zone_cut=240;
       8:zone_cut=480;
       9:zone_cut=720;
       10:zone_cut=960;
       11:zone_cut=1200;
       12:zone_cut=1440;
       default:zone_cut=1440;endcase
      default:zone_cut=1440;endcase end
    endfunction
    function [3:0] nominal_zone;
     input signed [15:0] angle;input [1:0] p;
     integer z;reg [3:0] count;
     begin count=p==1 ? 5 : p==2 ? 12 : 7;nominal_zone=0;
      for(z=1;z<12;z=z+1)if(z<count && angle>=zone_cut(p,z))nominal_zone=z;
     end
    endfunction
    wire signed [15:0] upper_boundary=zone_cut(profile,selected_zone+1'b1)+48;
    wire signed [15:0] lower_boundary=zone_cut(profile,selected_zone)-48;
    function signed [15:0] median3;
        input signed [15:0] a,b,c;
        begin
            if(a>b) median3=b>c ? b : a>c ? c : a;
            else median3=a>c ? a : b>c ? c : b;
        end
    endfunction
    reg zone_v1,zone_v2;reg signed[15:0]zone_angle_q;reg[1:0]zone_profile_q;
    reg crossing_q,zone_range_q,crossing2,range2;reg[3:0]zone_nominal_q;reg[31:0]zone_time_q,zone_time2;
    always @(posedge clk)begin
     if(!rst_n || sensor_restarted || !online || !calibrated || calibrating || accuracy<2 || layout_changed || !data_fresh || drift_warning)begin
      zone_v1<=0;zone_v2<=0;crossing2<=0;range2<=0;zone_angle_q<=0;zone_profile_q<=0;crossing_q<=0;zone_range_q<=0;zone_nominal_q<=0;zone_time_q<=0;zone_time2<=0;
     end else begin
      zone_v1<=pose_valid;zone_v2<=zone_v1;
      if(pose_valid)begin zone_angle_q<=smooth_yaw;zone_profile_q<=profile;zone_time_q<=wall_ticks;
       crossing_q<=(selected_zone<note_count-1 && smooth_yaw>=upper_boundary) || (selected_zone>0 && smooth_yaw<=lower_boundary);
       zone_range_q<=yaw>=-1440 && yaw<=1440;end
      if(zone_v1)begin crossing2<=crossing_q;range2<=zone_range_q;zone_nominal_q<=nominal_zone(zone_angle_q,zone_profile_q);zone_time2<=zone_time_q;end
     end
    end
    wire signed [15:0] stable_roll=median3(roll_history[1],roll_history[2],roll_history[3]);
    function [7:0] strength_velocity;
        input [15:0] a;
        reg [31:0] result;
        begin
            result=a<=HIT_THRESHOLD ? 32 : 32+((a-HIT_THRESHOLD)*21>>9);
            strength_velocity=result>127 ? 127 : result[7:0];
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            yaw_h1<=0;yaw_h2<=0;yaw_samples<=0;zone_candidate<=3;zone_since<=0;zone_pending<=0;wall_ticks<=0;selected_zone<=3;out_of_range<=0;drift_warning<=0;armed<=0;
            note_on<=0;velocity_update<=0;velocity<=0;hit_zone<=3;hit_profile<=0;previous_profile<=0;hit_octave<=0;hit_count<=0;event_id<=0;
            pose_age<=CLK_HZ;linear_age<=CLK_HZ;gyro_age<=CLK_HZ;linear_seen<=0;
            quiet_ticks<=0;refractory_ticks<=0;strength_ticks<=0;strength_active<=0;peak<=0;
            sample_event<=0;acceleration_hit<=0;jerk_hit<=0;have_previous<=0;
            previous_timestamp<=0;previous_sequence<=0;previous_down<=0;
            downward_accel<=0;processing_overruns<=0;last_trigger_reason<=0;
            previous_yaw<=0;have_yaw<=0;octave<=0;processing_overruns<=0;
            for(i=0;i<5;i=i+1) roll_history[i]<=0;
        end else begin
            wall_ticks<=wall_ticks+1'b1;
            if(!data_fresh || !online || calibrating || accuracy<2)begin zone_pending<=0;yaw_samples<=0;end
            note_on<=0;velocity_update<=0;sample_event<=0;
            if(pose_age<CLK_HZ) pose_age<=pose_age+1'b1;
            if(linear_age<CLK_HZ) linear_age<=linear_age+1'b1;
            if(gyro_age<CLK_HZ) gyro_age<=gyro_age+1'b1;
            if(gyro_valid) gyro_age<=0;
            if(pose_valid) begin
                pose_age<=0;previous_yaw<=yaw;have_yaw<=1;
                yaw_h1<=yaw;yaw_h2<=yaw_h1;if(yaw_samples<2)yaw_samples<=yaw_samples+1'b1;
                out_of_range<=yaw< -1440 || yaw>1440;
                // A large pose jump with little measured angular velocity is
                // treated as an unsafe origin change until recalibration.
                if(have_yaw && calibrated && !calibrating &&
                   (yaw_delta>480 || yaw_delta< -480) && gyro_speed<1536)
                    drift_warning<=1;
                roll_history[0]<=roll;
                for(i=1;i<5;i=i+1) roll_history[i]<=roll_history[i-1];
                if(octave==0) begin
                    if(stable_roll< -288) octave<=-1;
                    else if(stable_roll>288) octave<=1;
                end else if(octave<0 && stable_roll> -160) octave<=0;
                else if(octave>0 && stable_roll<160) octave<=0;
            end
            if(zone_v2 && online && calibrated && !calibrating && accuracy>=2 && data_fresh && !drift_warning && !layout_changed && !sensor_restarted)begin
             if(range2 && crossing2)begin
              if(!zone_pending || zone_candidate!=zone_nominal_q)begin zone_candidate<=zone_nominal_q;zone_since<=zone_time2;zone_pending<=1;end
              else if(zone_time2-zone_since>=CLK_HZ*3/100)begin selected_zone<=zone_candidate;zone_pending<=0;end
             end else zone_pending<=0;
            end
            if(calibrating) begin drift_warning<=0;have_yaw<=0;selected_zone<=note_count>>1;octave<=0;end
            if(linear_age>=CLK_HZ/25)begin have_previous<=0;linear_seen<=0;end
            if(linear_valid)begin
                if(linear_timestamp_valid &&
                   (!have_previous || (consecutive && interval_ok && linear_age<CLK_HZ/25)))begin
                    linear_age<=0;linear_seen<=1;sample_event<=1;
                    if(down_now>32767) downward_accel<=32767;
                    else downward_accel<=down_now[15:0];
                    // First sample seeds the derivative, never fires a hit.
                    acceleration_hit<=have_previous && down_now>=HIT_THRESHOLD;
                    jerk_hit<=have_previous && jerk_cross;
                    previous_timestamp<=linear_timestamp_ticks;
                    previous_sequence<=linear_sequence;previous_down<=down_now;have_previous<=1;
                end else begin
                    have_previous<=0;linear_seen<=0;sample_event<=0;
                    acceleration_hit<=0;jerk_hit<=0;armed<=0;quiet_ticks<=0;
                    processing_overruns<=processing_overruns+1'b1;
                end
            end
            if(refractory_ticks!=0) refractory_ticks<=refractory_ticks-1'b1;
            if(!playable) begin quiet_ticks<=0;armed<=0;strength_active<=0;end
            else begin
                if(quiet) begin
                    if(quiet_ticks<QUIET_TICKS) quiet_ticks<=quiet_ticks+1'b1;
                    if(quiet_ticks>=QUIET_TICKS && refractory_ticks==0) armed<=1;
                end else quiet_ticks<=0;
                if(sample_event && armed && (acceleration_hit || jerk_hit) && (!(snapshot_required===1'b1) || snapshot_valid)) begin
                    note_on<=1;last_trigger_reason<={jerk_hit,acceleration_hit};hit_zone<=snapshot_required===1'b1 ? snapshot_zone : selected_zone;hit_profile<=snapshot_required===1'b1 ? snapshot_profile : profile;hit_octave<=snapshot_required===1'b1 ? snapshot_octave : octave;
                    velocity<=strength_velocity(downward_accel);peak<=downward_accel;
                    event_id<=event_id+1'b1;hit_count<=hit_count+1'b1;
                    armed<=0;quiet_ticks<=0;refractory_ticks<=REFRACTORY_TICKS;
                    strength_ticks<=0;strength_active<=1;
                end
                if(strength_active) begin
                    if(sample_event && downward_accel>0 && downward_accel>peak) peak<=downward_accel;
                    if(strength_ticks==STRENGTH_TICKS-1) begin
                        velocity<=strength_velocity(sample_event && downward_accel>0 && downward_accel>peak ? downward_accel : peak);
                        velocity_update<=1;strength_active<=0;
                    end else strength_ticks<=strength_ticks+1'b1;
                end
            end
            previous_profile<=profile;
            if(layout_changed)begin
                selected_zone<=note_count>>1;armed<=0;quiet_ticks<=0;strength_active<=0;
                note_on<=0;velocity_update<=0;
            end
            // Recalibration, invalid quality, and layout changes cannot create a jerk edge.
            if(!online || !calibrated || calibrating || accuracy<2 || layout_changed)begin
                have_previous<=0;sample_event<=0;acceleration_hit<=0;jerk_hit<=0;
            end
            if(sensor_restarted) begin
                pose_age<=CLK_HZ;linear_age<=CLK_HZ;gyro_age<=CLK_HZ;linear_seen<=0;
                armed<=0;strength_active<=0;quiet_ticks<=0;refractory_ticks<=0;
                selected_zone<=note_count>>1;out_of_range<=0;drift_warning<=0;have_yaw<=0;octave<=0;
                have_previous<=0;linear_seen<=0;sample_event<=0;acceleration_hit<=0;jerk_hit<=0;
                downward_accel<=0;last_trigger_reason<=0;note_on<=0;velocity_update<=0;
                for(i=0;i<5;i=i+1) roll_history[i]<=0;
            end
        end
    end
endmodule

