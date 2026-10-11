// Autonomous single BNO08X UART-SHTP host. PS1 must be high, PS0 low.
// Queries buffer space before each write; transmitted bytes are >100 us apart.
module bno_uart_host #(
    parameter CLK_HZ=50000000,
    parameter RESET_TICKS=CLK_HZ/100,
    parameter BOOT_TICKS=CLK_HZ*3/4,
    parameter QUERY_TIMEOUT=CLK_HZ/5,
    parameter RETRY_TICKS=CLK_HZ*3,
    parameter TX_SPACING=CLK_HZ/5000,
    parameter MAX_AUTO_RESETS=2
)(
    input clk,input rst_n,input force_reset,input rx,
    output tx,output reg sensor_rst_n,output reg fault_latched,
    output reg online,output reg [4:0] feature_mask,
    output [2:0] link_state,output reg [31:0] reset_attempts,
    output quat_valid,output signed [15:0] qx,qy,qz,qw,output [1:0] accuracy,
    output accel_valid,gyro_valid,gravity_valid,linear_valid,
    output signed [15:0] ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz,
    output reg [15:0] pose_hz,accel_hz,gyro_hz,
    output [31:0] protocol_errors,sequence_gaps,
    output reg sensor_restarted,
    output [15:0] received_bytes,received_packets,output reg [2:0] stream_fresh
);
    wire packet_ready,packet_take,buffer_status_valid;
    wire [9:0] packet_length;
    wire [8:0] read_addr;
    wire [7:0] read_data;
    wire [15:0] buffer_available;
    wire [31:0] link_errors,overruns,malformed,unsupported;
    wire feature_valid,product_valid,hub_reset;
    wire [7:0] feature_id;
    wire [31:0] feature_interval_us;
    wire signed [31:0] sensor_offset_us;
    reg [3:0] init_state,command_index;
    reg [31:0] timer,watchdog,rate_timer;
    reg [31:0] auto_resets;
    reg force_previous;
    wire manual_reset=force_reset && !force_previous;
    reg [31:0] pose_age,accel_age,gyro_age;
    reg pose_seen,accel_seen,gyro_seen;
    reg [15:0] pose_count,accel_count,gyro_count;
    reg buffer_known;
    reg [15:0] available;
    reg sending,query,escape_phase;
    reg [5:0] tx_pos;
    reg [7:0] control_sequence;
    reg tx_done;
    wire tx_ready;
    wire [7:0] raw_byte;
    wire needs_escape=raw_byte==8'h7e || raw_byte==8'h7d;
    wire boundary=tx_pos==0 || tx_pos==last_pos;
    wire [7:0] serial_byte=(!boundary && needs_escape && !escape_phase) ? 8'h7d :
                              escape_phase ? (raw_byte ^ 8'h20) : raw_byte;
    wire [5:0] cargo_length=(command_index==0 || !command_index[0]) ? 6 : 21;
    wire [5:0] last_pos=query ? 2 : cargo_length+2;
    wire [2:0] feature_index=(command_index-1'b1)>>1;
    function [7:0] report_id;
        input [2:0] index;
        begin case(index)
            0:report_id=8'h28;
            1:report_id=1;
            2:report_id=2;
            3:report_id=4;
            4:report_id=6;
            default:report_id=0;
        endcase end
    endfunction
    function [31:0] interval_for;
        input [2:0] index;
        begin case(index)
            1:interval_for=2000;
            3:interval_for=2500;
            default:interval_for=5000;
        endcase end
    endfunction
    function [7:0] message_byte;
        input is_query;
        input [5:0] position;
        input [3:0] cmd_index;
        input [7:0] seq;
        reg [31:0] interval;
        reg [2:0] index;
        begin
            index=(cmd_index-1'b1)>>1;
            interval=interval_for(index);
            message_byte=0;
            if(is_query) begin
                if(position==0 || position==2) message_byte=8'h7e;
            end else begin
                case(position)
                    0:message_byte=8'h7e;
                    1:message_byte=1;
                    2:message_byte=(cmd_index==0 || !cmd_index[0]) ? 6 : 21;
                    4:message_byte=2;
                    5:message_byte=seq;
                    6:message_byte=cmd_index==0 ? 8'hf9 : cmd_index[0] ? 8'hfd : 8'hfe;
                    7:message_byte=cmd_index==0 ? 0 : report_id(index);
                    11:message_byte=interval[7:0];
                    12:message_byte=interval[15:8];
                    13:message_byte=interval[23:16];
                    14:message_byte=interval[31:24];
                endcase
                if(position==((cmd_index==0 || !cmd_index[0]) ? 8 : 23)) message_byte=8'h7e;
            end
        end
    endfunction
    assign raw_byte=message_byte(query,tx_pos,command_index,control_sequence);
    // Register the public validity flag to isolate the age comparators from
    // downstream Voice updates. Evaluate the next age/seen values so accepting
    // a report and crossing a timeout keep their original clock-edge semantics.
    wire next_pose_fresh=quat_valid || (pose_seen && pose_age<CLK_HZ/10-1);
    wire next_accel_fresh=accel_valid || (accel_seen && accel_age<CLK_HZ/20-1);
    wire next_gyro_fresh=gyro_valid || (gyro_seen && gyro_age<CLK_HZ/10-1);
    assign protocol_errors=link_errors+overruns+malformed+unsupported;
    assign link_state=fault_latched ? 5 : !sensor_rst_n ? 0 : init_state==1 ? 1 : online ? 3 : init_state==7 ? 4 : 2;
    shtp_uart_link #(.CLK_HZ(CLK_HZ),.TX_SPACING(TX_SPACING)) link(
        .clk(clk),.rst_n(rst_n && sensor_rst_n),.rx(rx),.tx(tx),
        .tx_data(serial_byte),.tx_valid(sending),.tx_ready(tx_ready),
        .packet_ready(packet_ready),.packet_take(packet_take),.packet_length(packet_length),
        .read_addr(read_addr),.read_data(read_data),.buffer_status_valid(buffer_status_valid),
        .buffer_available(buffer_available),.errors(link_errors),.overruns(overruns),
        .received_bytes(received_bytes),.received_packets(received_packets));
    shtp_report_decode decoder(
        .clk(clk),.rst_n(rst_n && sensor_rst_n),.packet_ready(packet_ready),
        .packet_length(packet_length),.packet_take(packet_take),.read_addr(read_addr),.read_data(read_data),
        .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),
        .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
        .gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(lz),
        .feature_valid(feature_valid),.feature_id(feature_id),.feature_interval_us(feature_interval_us),
        .product_valid(product_valid),.hub_reset(hub_reset),.malformed(malformed),
        .unsupported(unsupported),.sequence_gaps(sequence_gaps),.sensor_offset_us(sensor_offset_us));
    integer fi;
    always @(posedge clk) begin
        if(!rst_n) begin
            init_state<=0;command_index<=0;timer<=0;watchdog<=0;
            sensor_rst_n<=0;online<=0;stream_fresh<=0;reset_attempts<=0;feature_mask<=0;
            auto_resets<=0;fault_latched<=0;force_previous<=0;
            sending<=0;query<=0;escape_phase<=0;tx_pos<=0;control_sequence<=0;tx_done<=0;
            buffer_known<=0;available<=0;
            pose_age<=CLK_HZ;accel_age<=CLK_HZ;gyro_age<=CLK_HZ;
            pose_seen<=0;accel_seen<=0;gyro_seen<=0;sensor_restarted<=0;
            rate_timer<=0;pose_count<=0;accel_count<=0;gyro_count<=0;
            pose_hz<=0;accel_hz<=0;gyro_hz<=0;
        end else begin
            force_previous<=force_reset;
            tx_done<=0;sensor_restarted<=0;
            online<=next_pose_fresh && next_accel_fresh && next_gyro_fresh;
            stream_fresh<={next_gyro_fresh,next_accel_fresh,next_pose_fresh};
            if(pose_age<CLK_HZ) pose_age<=pose_age+1'b1;
            if(accel_age<CLK_HZ) accel_age<=accel_age+1'b1;
            if(gyro_age<CLK_HZ) gyro_age<=gyro_age+1'b1;
            if(quat_valid) begin pose_age<=0;pose_seen<=1;pose_count<=pose_count+1'b1;end
            if(accel_valid) begin accel_age<=0;accel_seen<=1;accel_count<=accel_count+1'b1;end
            if(gyro_valid) begin gyro_age<=0;gyro_seen<=1;gyro_count<=gyro_count+1'b1;end
            if(rate_timer==CLK_HZ-1) begin
                rate_timer<=0;pose_hz<=pose_count;accel_hz<=accel_count;gyro_hz<=gyro_count;
                pose_count<=quat_valid ? 1 : 0;accel_count<=accel_valid ? 1 : 0;gyro_count<=gyro_valid ? 1 : 0;
            end else rate_timer<=rate_timer+1'b1;
            if(buffer_status_valid) begin available<=buffer_available;buffer_known<=1;end
            if(feature_valid && feature_interval_us!=0)
                for(fi=0;fi<5;fi=fi+1) if(feature_id==report_id(fi)) feature_mask[fi]<=1;
            if(sending && tx_ready) begin
                if(!boundary && needs_escape && !escape_phase) escape_phase<=1;
                else begin
                    escape_phase<=0;
                    if(tx_pos==last_pos) begin sending<=0;tx_done<=1;end
                    else tx_pos<=tx_pos+1'b1;
                end
            end
            case(init_state)
                0:if(timer==RESET_TICKS-1) begin timer<=0;sensor_rst_n<=1;init_state<=1;end
                  else timer<=timer+1'b1;
                1:if(timer==BOOT_TICKS-1) begin timer<=0;command_index<=0;control_sequence<=0;init_state<=2;end
                  else timer<=timer+1'b1;
                2:if(!sending) begin
                    query<=1;tx_pos<=0;escape_phase<=0;sending<=1;buffer_known<=0;available<=0;init_state<=3;
                end
                3:if(tx_done) begin timer<=0;init_state<=4;end
                4:if(buffer_known && available>=cargo_length) begin
                    query<=0;tx_pos<=0;escape_phase<=0;sending<=1;available<=available-cargo_length;init_state<=5;
                  end else if(timer==QUERY_TIMEOUT-1) begin timer<=0;init_state<=2;end
                  else timer<=timer+1'b1;
                5:if(tx_done) begin
                    control_sequence<=control_sequence+1'b1;timer<=0;init_state<=6;
                end
                6:if(timer==CLK_HZ/1000-1) begin
                    timer<=0;
                    if(command_index==10) init_state<=7;
                    else begin command_index<=command_index+1'b1;init_state<=2;end
                  end else timer<=timer+1'b1;
                7:begin end
                9:begin online<=0;stream_fresh<=0;end
                default:init_state<=0;
            endcase
            // Recovery does not wait for any PC command. Fresh stream data
            // refreshes watchdog even while the feature sequence is running.
            if(next_pose_fresh && next_accel_fresh && next_gyro_fresh) watchdog<=0;
            else if(sensor_rst_n && init_state!=1) watchdog<=watchdog+1'b1;
            if(manual_reset || (!fault_latched && ((hub_reset && init_state>1) || watchdog>=RETRY_TICKS))) begin
                sensor_rst_n<=0;online<=0;stream_fresh<=0;timer<=0;watchdog<=0;sending<=0;
                if(manual_reset)begin fault_latched<=0;auto_resets<=0;init_state<=0;reset_attempts<=reset_attempts+1'b1;end
                else if(auto_resets>=MAX_AUTO_RESETS)begin fault_latched<=1;init_state<=9;end
                else begin auto_resets<=auto_resets+1'b1;init_state<=0;reset_attempts<=reset_attempts+1'b1;end
                pose_seen<=0;accel_seen<=0;gyro_seen<=0;feature_mask<=0;buffer_known<=0;
                pose_hz<=0;accel_hz<=0;gyro_hz<=0;pose_count<=0;accel_count<=0;gyro_count<=0;rate_timer<=0;
                sensor_restarted<=1;
            end
        end
    end
endmodule
