// SH-2 bounded report decoder. No computer participates in this data path.
// Supports batched base/rebase records and 01/02/04/06/05/08/28 reports.
module shtp_report_decode #(parameter REPORT_BACKPRESSURE=0)(
    input clk,input rst_n,input packet_ready,input [9:0] packet_length,
    input [31:0] packet_hint_ticks,input packet_hint_valid,
    input linear_ready,
    output reg packet_take,output [8:0] read_addr,input [7:0] read_data,
    output reg [7:0] quat_sequence,output reg [31:0] quat_timestamp_ticks,output reg quat_timestamp_valid,
    output reg quat_valid,output reg signed [15:0] qx,qy,qz,qw,
    output reg [1:0] accuracy,accel_accuracy,gyro_accuracy,
    output reg accel_valid,output reg gyro_valid,output reg gravity_valid,
    output reg [7:0] linear_sequence,output reg linear_valid,
    output reg [31:0] linear_timestamp_ticks,output reg linear_timestamp_valid,
    output reg signed [15:0] ax,ay,az,gx,gy,gz,
    output reg signed [15:0] gravity_x,gravity_y,gravity_z,lx,ly,lz,
    output reg feature_valid,output reg [7:0] feature_id,
    output reg [31:0] feature_interval_us,
    output reg product_valid,output reg hub_reset,
    output reg [31:0] malformed,unsupported,sequence_gaps,
    output reg signed [31:0] sensor_offset_us
);
    reg [2:0] state;
    reg [9:0] length,pos;
    reg [7:0] channel,rid;
    reg [4:0] field,report_size;
    reg [7:0] data[0:16];
    reg [7:0] next_sequence[0:5];
    reg [5:0] sequence_seen;
    reg signed [31:0] base_ticks;
    reg [31:0] cargo_hint_ticks;
    reg cargo_hint_valid,base_seen;
    reg [33:0] quat_norm;
    reg signed [15:0] component;
    integer i;
    assign read_addr=pos[8:0];
    function [4:0] size_for;
        input [7:0] id;
        begin case(id)
            8'hfb,8'hfa:size_for=5;
            1,2,4,6:size_for=10;
            5,8'h28:size_for=14;
            8:size_for=12;
            8'hfc:size_for=17;
            8'hf8:size_for=16;
            default:size_for=0;
        endcase end
    endfunction
    wire [15:0] word0={data[5],data[4]};
    wire [15:0] word1={data[7],data[6]};
    wire [15:0] word2={data[9],data[8]};
    wire [15:0] word3={data[11],data[10]};
    wire [31:0] word32={data[4],data[3],data[2],data[1]};
    wire [13:0] delay_ticks={data[2][7:2],data[3]};
    wire [7:0] previous_sequence=next_sequence[channel]-8'd1;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=0;pos<=0;length<=0;channel<=0;rid<=0;
            field<=0;report_size<=0;packet_take<=0;sequence_seen<=0;
            quat_valid<=0;accel_valid<=0;gyro_valid<=0;gravity_valid<=0;linear_valid<=0;
            quat_sequence<=0;quat_timestamp_ticks<=0;quat_timestamp_valid<=0;
            feature_valid<=0;product_valid<=0;hub_reset<=0;feature_id<=0;feature_interval_us<=0;
            qx<=0;qy<=0;qz<=0;qw<=16384;accuracy<=0;accel_accuracy<=0;gyro_accuracy<=0;
            ax<=0;ay<=0;az<=0;gx<=0;gy<=0;gz<=0;
            gravity_x<=0;gravity_y<=0;gravity_z<=0;lx<=0;ly<=0;lz<=0;linear_sequence<=0;
            malformed<=0;unsupported<=0;sequence_gaps<=0;
            base_ticks<=0;sensor_offset_us<=0;quat_norm<=0;component<=0;
            cargo_hint_ticks<=0;cargo_hint_valid<=0;base_seen<=0;
            linear_timestamp_ticks<=0;linear_timestamp_valid<=0;
            for(i=0;i<6;i=i+1) next_sequence[i]<=0;
            for(i=0;i<17;i=i+1) data[i]<=0;
        end else begin
            packet_take<=0;quat_valid<=0;accel_valid<=0;gyro_valid<=0;
            gravity_valid<=0;linear_valid<=0;feature_valid<=0;product_valid<=0;hub_reset<=0;
            case(state)
                0:if(packet_ready && !packet_take) begin
                    length<=packet_length;pos<=2;state<=1;base_ticks<=0;base_seen<=0;
                    cargo_hint_ticks<=packet_hint_ticks;cargo_hint_valid<=packet_hint_valid;
                end
                1:begin channel<=read_data;pos<=3;state<=2;end
                2:begin
                    pos<=4;
                    if(channel>5 || length<4 || length>512) begin
                        malformed<=malformed+1'b1;state<=7;
                    end else if(sequence_seen[channel] && read_data==previous_sequence) begin
                        // A repeated cargo must not refresh ages, calibration
                        // or performance events as if it were a new sample.
                        sequence_gaps<=sequence_gaps+1'b1;malformed<=malformed+1'b1;state<=7;
                    end else begin
                        if(sequence_seen[channel] && read_data!=next_sequence[channel])
                            sequence_gaps<=sequence_gaps+1'b1;
                        next_sequence[channel]<=read_data+1'b1;
                        sequence_seen[channel]<=1;
                        state<=3;
                    end
                end
                3:if(pos>=length) state<=7;
                  else if(channel==1) begin
                      if(read_data==1) begin hub_reset<=1;sequence_seen<=0;end
                      state<=7;
                  end else if(channel==2 || channel==3 || channel==4) begin
                      if(size_for(read_data)==0) begin unsupported<=unsupported+1'b1;state<=7;end
                      else if(pos+size_for(read_data)>length) begin malformed<=malformed+1'b1;state<=7;end
                      else begin
                          rid<=read_data;report_size<=size_for(read_data);
                          field<=0;state<=4;quat_norm<=0;
                      end
                  end else state<=7;
                4:begin
                    data[field]<=read_data;pos<=pos+1'b1;field<=field+1'b1;
                    if((rid==5 || rid==8 || rid==8'h28) && field>=5 && field<=11 && field[0]) begin
                        component={read_data,data[field-1'b1]};
                        // $unsigned() makes its argument self-sized; explicitly
                        // widen both operands so a Q14 square retains 32 bits.
                        quat_norm<=quat_norm + $unsigned(
                            $signed({{16{component[15]}},component}) *
                            $signed({{16{component[15]}},component}));
                    end
                    if(field+1==report_size) state<=5;
                end
                5:if(!REPORT_BACKPRESSURE || rid!=4 || (channel!=3 && channel!=4) || linear_ready)begin
                    state<=3;
                    if(rid==8'hfb)begin base_ticks<=-$signed(word32);base_seen<=1;end
                    else if(rid==8'hfa) base_ticks<=base_ticks+$signed(word32);
                    else if(channel==2 && rid==8'hfc) begin
                        feature_id<=data[1];feature_interval_us<={data[8],data[7],data[6],data[5]};feature_valid<=1;
                    end else if(channel==2 && rid==8'hf8) product_valid<=1;
                    else if(channel==3 || channel==4) begin
                        sensor_offset_us<=(base_ticks+$signed({1'b0,delay_ticks}))*100;
                        case(rid)
                            1:begin accel_accuracy<=data[2][1:0];ax<=word0;ay<=word1;az<=word2;accel_valid<=1;end
                            2:begin gyro_accuracy<=data[2][1:0];gx<=word0;gy<=word1;gz<=word2;gyro_valid<=1;end
                            4:begin
                                linear_sequence<=data[1];lx<=word0;ly<=word1;lz<=word2;linear_valid<=1;
                                // Modulo 2^32 subtraction later handles host clock wrap.
                                linear_timestamp_ticks<=cargo_hint_ticks+base_ticks+{18'd0,delay_ticks};
                                linear_timestamp_valid<=cargo_hint_valid && base_seen;
                            end
                            6:begin gravity_x<=word0;gravity_y<=word1;gravity_z<=word2;gravity_valid<=1;end
                            5,8,8'h28:begin
                                if(quat_norm>=34'd214748364 && quat_norm<=34'd322122547) begin
                                    qx<=word0;qy<=word1;qz<=word2;qw<=word3;
                                    accuracy<=data[2][1:0];quat_valid<=1;
                                    quat_sequence<=data[1];
                                    quat_timestamp_ticks<=cargo_hint_ticks+base_ticks+{18'd0,delay_ticks};
                                    quat_timestamp_valid<=cargo_hint_valid && base_seen;
                                end else malformed<=malformed+1'b1;
                            end
                        endcase
                    end
                end
                7:begin packet_take<=1;state<=0;end
                default:state<=0;
            endcase
        end
    end
endmodule
