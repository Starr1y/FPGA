// RETAINED_SPI_FAILURE_DIAGNOSTICS
// Autonomous SPI-SHTP configuration and report freshness; no PC dependency.
module bno_i2c_host #(
    parameter REPORT_BACKPRESSURE=0,
    parameter CLK_HZ=50000000,
    parameter RESET_TICKS=CLK_HZ/100,
    parameter BOOT_TICKS=CLK_HZ*3/4,
    parameter QUERY_TIMEOUT=CLK_HZ/5,
    parameter RETRY_TICKS=CLK_HZ*3,
    parameter HALF_DIV=25, parameter WAIT_CS_ACK=0,
    parameter MAX_AUTO_RESETS=2,
    parameter RESET_SETUP_TICKS=CLK_HZ/100000,
    parameter CS_SETUP_TICKS=(CLK_HZ/200000>0 ? CLK_HZ/200000 : 1),
    parameter CS_ACK_TIMEOUT=(CLK_HZ/1000>CS_SETUP_TICKS ? CLK_HZ/1000 : CS_SETUP_TICKS+1)
)(
    input clk,input rst_n,input force_reset,input miso,input scl_in,input int_n,input linear_ready,
    output sck,output cs_n,output mosi,output wake_n,output reg address_ack,output reg sensor_rst_n,output reg fault_latched,
    output reg online,output reg [4:0] feature_mask,
    output [2:0] link_state,output reg [31:0] reset_attempts,
    output quat_valid,output signed [15:0] qx,qy,qz,qw,output [1:0] accuracy,accel_accuracy,gyro_accuracy,
    output [7:0] linear_sequence,output [31:0] linear_timestamp_ticks,output linear_timestamp_valid,
    output accel_valid,gyro_valid,gravity_valid,linear_valid,
    output signed [15:0] ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz,
    output reg [15:0] pose_hz,accel_hz,gyro_hz,
    output [31:0] protocol_errors,sequence_gaps,
    output reg sensor_restarted,
    output [15:0] received_bytes,received_packets,output reg [2:0] stream_fresh,
    output reg [3:0] first_failure_reason,output reg [3:0] failure_reason,output reg [15:0] failure_header,output reg [1:0] failure_inputs
);
    wire packet_ready,packet_take,startup_seen;
    wire [9:0] packet_length;
    wire [31:0] packet_hint_ticks;wire packet_hint_valid;
    wire [8:0] read_addr;
    wire [7:0] read_data;
    wire [15:0] buffer_available;
    wire [31:0] link_errors,overruns,malformed,unsupported;
    wire [15:0] live_bytes,live_packets,last_header;
    wire sampled_int_n,sampled_miso;wire [3:0] transport_failure;wire live_address_ack;
    reg [15:0] failed_bytes,failed_packets;
    reg [31:0] failed_errors;
    reg [15:0] base_bytes,base_packets;
    reg [31:0] base_errors;
    wire [31:0] attempt_errors=link_errors+overruns+malformed+unsupported;
    function [15:0] sat16;
      input [15:0] a,b;reg [16:0] sum;
      begin sum={1'b0,a}+{1'b0,b};sat16=sum[16] ? 16'hffff : sum[15:0];end
    endfunction
    function [31:0] sat32;
      input [31:0] a,b;reg [32:0] sum;
      begin sum={1'b0,a}+{1'b0,b};sat32=sum[32] ? 32'hffffffff : sum[31:0];end
    endfunction
    assign received_bytes=fault_latched ? failed_bytes : sat16(base_bytes,link_running ? live_bytes : 16'd0);
    assign received_packets=fault_latched ? failed_packets : sat16(base_packets,link_running ? live_packets : 16'd0);
    wire feature_valid,product_valid,hub_reset;
    wire [7:0] feature_id;
    wire [31:0] feature_interval_us;
    wire signed [31:0] sensor_offset_us;
    reg [3:0] init_state,command_index;
    reg [31:0] timer,watchdog,rate_timer;
    reg [31:0] auto_resets;
    reg force_previous;
    wire manual_reset=force_reset && !force_previous;
    localparam PREPARE_RESET=8,FAULT=9;
    wire link_running=sensor_rst_n && init_state!=PREPARE_RESET && !fault_latched;
    wire link_sck,link_mosi;wire link_cs_n=1;wire link_wake_n=1;
    // Restore PS0 and idle bus before asserting RST, including recovery in WAKE.
    assign sck=link_running ? link_sck : 1'b0;
    assign cs_n=link_running ? link_cs_n : 1'b1;
    assign mosi=link_running ? link_mosi : 1'b0;
    assign wake_n=link_running ? link_wake_n : 1'b1;
    reg [31:0] pose_age,accel_age,gyro_age;
    reg pose_seen,accel_seen,gyro_seen;
    reg [15:0] pose_count,accel_count,gyro_count;
    reg buffer_known;
    reg [15:0] available;
    reg [7:0] control_sequence;
    wire tx_done,spi_busy;
    reg [167:0] tx_payload;reg [7:0] tx_length;
    wire [2:0] feature_index=(command_index-1'b1)>>1;
    wire [31:0] interval=interval_for(feature_index);
    function [7:0] report_id;
        input [2:0] index;
        begin case(index)
            // Relative hand control: six-axis, no magnetic heading reference.
            0:report_id=8'h08;
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
            default:interval_for=10000;
        endcase end
    endfunction
    always @*begin
        tx_length=(command_index==0 || !command_index[0]) ? 6 : 21;
        tx_payload=0;
        tx_payload[7:0]=tx_length;tx_payload[23:16]=2;tx_payload[31:24]=control_sequence;
        tx_payload[39:32]=command_index==0 ? 8'hf9 : command_index[0] ? 8'hfd : 8'hfe;
        tx_payload[47:40]=command_index==0 ? 0 : report_id(feature_index);
        if(command_index!=0 && command_index[0])tx_payload[103:72]=interval;
    end
    wire next_pose_fresh=quat_valid || (pose_seen && pose_age<CLK_HZ/10-1);
    wire next_accel_fresh=accel_valid || (accel_seen && accel_age<CLK_HZ/20-1);
    wire next_gyro_fresh=gyro_valid || (gyro_seen && gyro_age<CLK_HZ/10-1);
    assign protocol_errors=fault_latched ? failed_errors : sat32(base_errors,link_running ? attempt_errors : 32'd0);
    assign link_state=fault_latched ? 5 : !sensor_rst_n || init_state==PREPARE_RESET ? 0 : init_state==1 ? 1 : online ? 3 : init_state==7 ? 4 : 2;
    shtp_i2c_link #(.CLK_HZ(CLK_HZ),.HALF_DIV(HALF_DIV)) link(
        .clk(clk),.rst_n(rst_n && link_running),.enable(1'b1),.int_n(int_n),.miso(miso),
        .scl_in(scl_in),.scl_low(link_sck),.sda_low(link_mosi),.address_ack(live_address_ack),
        .tx_request(init_state==2),.tx_length(tx_length),.tx_payload(tx_payload),
        .tx_done(tx_done),.busy(spi_busy),.startup_seen(startup_seen),
        .packet_ready(packet_ready),.packet_take(packet_take),.packet_length(packet_length),
        .packet_hint_ticks(packet_hint_ticks),.packet_hint_valid(packet_hint_valid),
        .read_addr(read_addr),.read_data(read_data),.errors(link_errors),
        .received_bytes(live_bytes),.received_packets(live_packets),.last_header(last_header),
        .sampled_int_n(sampled_int_n),.sampled_miso(sampled_miso),.transport_failure(transport_failure));
    assign overruns=0;
    shtp_report_decode #(.REPORT_BACKPRESSURE(REPORT_BACKPRESSURE)) decoder(
        .clk(clk),.rst_n(rst_n && link_running),.packet_ready(packet_ready),
        .packet_length(packet_length),.packet_take(packet_take),.read_addr(read_addr),.read_data(read_data),
        .packet_hint_ticks(packet_hint_ticks),.packet_hint_valid(packet_hint_valid),
        .linear_ready(linear_ready),
        .quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(accuracy),.accel_accuracy(accel_accuracy),.gyro_accuracy(gyro_accuracy),
        .accel_valid(accel_valid),.gyro_valid(gyro_valid),.gravity_valid(gravity_valid),.linear_valid(linear_valid),.linear_sequence(linear_sequence),
        .linear_timestamp_ticks(linear_timestamp_ticks),.linear_timestamp_valid(linear_timestamp_valid),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
        .gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(lz),
        .feature_valid(feature_valid),.feature_id(feature_id),.feature_interval_us(feature_interval_us),
        .product_valid(product_valid),.hub_reset(hub_reset),.malformed(malformed),
        .unsupported(unsupported),.sequence_gaps(sequence_gaps),.sensor_offset_us(sensor_offset_us));
    wire [3:0] attempt_reason=transport_failure!=0 ? transport_failure : !startup_seen ? 1 :
      link_errors!=0 ? 2 : malformed!=0 || unsupported!=0 ? 4 : feature_mask!=31 ? 5 :
      !next_pose_fresh ? 6 : !next_accel_fresh ? 7 : !next_gyro_fresh ? 9 : 10;
    integer fi;
    always @(posedge clk) begin
        if(!rst_n) begin
            init_state<=PREPARE_RESET;command_index<=0;timer<=0;watchdog<=0;
            sensor_rst_n<=1;online<=0;stream_fresh<=0;reset_attempts<=0;feature_mask<=0;
            auto_resets<=0;fault_latched<=0;force_previous<=0;
            base_bytes<=0;base_packets<=0;base_errors<=0;first_failure_reason<=0;failed_bytes<=0;failed_packets<=0;failed_errors<=0;failure_reason<=0;failure_header<=0;failure_inputs<=0;
            control_sequence<=0;address_ack<=0;

            pose_age<=CLK_HZ;accel_age<=CLK_HZ;gyro_age<=CLK_HZ;
            pose_seen<=0;accel_seen<=0;gyro_seen<=0;sensor_restarted<=0;
            rate_timer<=0;pose_count<=0;accel_count<=0;gyro_count<=0;
            pose_hz<=0;accel_hz<=0;gyro_hz<=0;
        end else begin
            force_previous<=force_reset;
            if(manual_reset)address_ack<=0;else if(live_address_ack)address_ack<=1;
            sensor_restarted<=0;
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

            if(feature_valid && feature_interval_us!=0)
                for(fi=0;fi<5;fi=fi+1) if(feature_id==report_id(fi)) feature_mask[fi]<=1;
            case(init_state)
                PREPARE_RESET:if(timer>=RESET_SETUP_TICKS-1)begin timer<=0;sensor_rst_n<=0;init_state<=0;end
                  else timer<=timer+1'b1;
                0:if(timer==RESET_TICKS-1)begin timer<=0;sensor_rst_n<=1;init_state<=1;end
                  else timer<=timer+1'b1;
                1:if(timer>=BOOT_TICKS-1)begin
                    if(!spi_busy && !packet_ready && !hub_reset)begin timer<=0;command_index<=0;control_sequence<=0;init_state<=2;end
                  end else timer<=timer+1'b1;
                2:if(tx_done)begin control_sequence<=control_sequence+1'b1;timer<=0;init_state<=6;end
                6:if(timer==CLK_HZ/1000-1)begin
                    timer<=0;
                    if(command_index==10)init_state<=7;
                    else begin command_index<=command_index+1'b1;init_state<=2;end
                  end else timer<=timer+1'b1;
                7:begin end
                FAULT:begin online<=0;stream_fresh<=0;end
                default:init_state<=0;
            endcase
            // Recovery does not wait for any PC command. Fresh stream data
            // refreshes watchdog even while the feature sequence is running.
            // A partial stream must not keep a nonfunctional controller alive.
            if(next_pose_fresh && next_accel_fresh && next_gyro_fresh) watchdog<=0;
            else if(link_running) watchdog<=watchdog+1'b1;
            if(hub_reset && init_state>1 && init_state!=PREPARE_RESET && !fault_latched)begin
                init_state<=1;timer<=0;command_index<=0;control_sequence<=0;
                feature_mask<=0;online<=0;stream_fresh<=0;watchdog<=0;
                pose_seen<=0;accel_seen<=0;gyro_seen<=0;sensor_restarted<=1;
            end
            if(manual_reset || (!fault_latched && init_state!=PREPARE_RESET &&
               watchdog>=RETRY_TICKS)) begin
                online<=0;stream_fresh<=0;timer<=0;watchdog<=0;
                if(manual_reset)begin base_bytes<=0;base_packets<=0;base_errors<=0;first_failure_reason<=0;failure_reason<=0;failure_header<=0;failure_inputs<=0;fault_latched<=0;auto_resets<=0;init_state<=PREPARE_RESET;reset_attempts<=reset_attempts+1'b1;end
                else if(auto_resets>=MAX_AUTO_RESETS)begin
                    fault_latched<=1;init_state<=FAULT;
                    failed_bytes<=sat16(base_bytes,live_bytes);failed_packets<=sat16(base_packets,live_packets);
                    failed_errors<=sat32(base_errors,attempt_errors);failure_reason<=attempt_reason;
                end
                else begin
                    base_bytes<=sat16(base_bytes,live_bytes);base_packets<=sat16(base_packets,live_packets);
                    base_errors<=sat32(base_errors,attempt_errors);
                    auto_resets<=auto_resets+1'b1;init_state<=PREPARE_RESET;reset_attempts<=reset_attempts+1'b1;
                end
                if(!manual_reset && first_failure_reason==0)begin
                    first_failure_reason<=attempt_reason;failure_header<=last_header;
                    failure_inputs<={sampled_int_n,sampled_miso};
                end
                pose_seen<=0;accel_seen<=0;gyro_seen<=0;
                if(manual_reset || auto_resets<MAX_AUTO_RESETS)feature_mask<=0;
                buffer_known<=0;
                pose_hz<=0;accel_hz<=0;gyro_hz<=0;pose_count<=0;accel_count<=0;gyro_count<=0;rate_timer<=0;
                sensor_restarted<=1;
            end
            if(!link_running || fault_latched)begin
                online<=0;stream_fresh<=0;
                pose_seen<=0;accel_seen<=0;gyro_seen<=0;
                pose_age<=CLK_HZ;accel_age<=CLK_HZ;gyro_age<=CLK_HZ;
            end
        end
    end
endmodule
