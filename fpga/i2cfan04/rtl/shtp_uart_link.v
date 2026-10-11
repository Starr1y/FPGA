// Native SHTP packets over BNO08X 3 Mbps UART, RFC1662 flags/escaping.
// Two receive banks decouple autonomous decoding from the incoming byte stream.
module shtp_uart_link #(
    parameter CLK_HZ=50000000,
    parameter BAUD=3000000,
    parameter TX_SPACING=CLK_HZ/5000,
    parameter RX_TIMEOUT=CLK_HZ/200
)(
    input clk, input rst_n, input rx, output tx,
    input [7:0] tx_data, input tx_valid, output tx_ready,
    output reg packet_ready, input packet_take,
    output reg [9:0] packet_length,
    input [8:0] read_addr, output [7:0] read_data,
    output reg buffer_status_valid, output reg [15:0] buffer_available,
    output reg [31:0] errors, output reg [31:0] overruns,
    output reg [15:0] received_bytes,received_packets
);
    wire [7:0] incoming;
    wire byte_valid, byte_start, byte_error, serial_ready;
    uart_rx #(.CLK_HZ(CLK_HZ)) receiver(clk,rst_n,rx,BAUD,
                                         incoming,byte_valid,byte_start,byte_error);
    reg [31:0] tx_pause;
    assign tx_ready=serial_ready && tx_pause==0;
    uart_tx #(.CLK_HZ(CLK_HZ)) sender(clk,rst_n,BAUD,tx_data,
                                     tx_valid && tx_ready,serial_ready,tx);
    reg [7:0] mem[0:1023];
    reg write_bank,read_bank;
    assign read_data=mem[{read_bank,read_addr}];
    reg active,escaped,have_protocol,bad_frame;
    reg [7:0] protocol_id;
    reg [9:0] count;
    reg [15:0] declared_length,control_value;
    reg [31:0] idle_ticks;
    wire [7:0] unescaped=incoming ^ (escaped ? 8'h20 : 8'h00);
    always @(posedge clk) begin
        if(!rst_n) begin
            tx_pause<=0;packet_ready<=0;packet_length<=0;
            write_bank<=0;read_bank<=1;active<=0;escaped<=0;
            have_protocol<=0;bad_frame<=0;protocol_id<=0;count<=0;
            declared_length<=0;control_value<=0;idle_ticks<=0;
            buffer_status_valid<=0;buffer_available<=0;errors<=0;overruns<=0;
            received_bytes<=0;received_packets<=0;
        end else begin
            buffer_status_valid<=0;
            if(byte_valid && received_bytes!=16'hffff)received_bytes<=received_bytes+1'b1;
            if(tx_pause!=0) tx_pause<=tx_pause-1'b1;
            if(tx_valid && tx_ready) tx_pause<=TX_SPACING-1;
            if(packet_take) packet_ready<=0;
            if(active && have_protocol) begin
                if(idle_ticks==RX_TIMEOUT-1) begin
                    active<=0;count<=0;escaped<=0;errors<=errors+1'b1;
                end else idle_ticks<=idle_ticks+1'b1;
            end
            if(byte_error) begin
                active<=0;count<=0;escaped<=0;errors<=errors+1'b1;
            end else if(byte_valid) begin
                idle_ticks<=0;
                if(incoming==8'h7e) begin
                    if(active && have_protocol) begin
                        if(bad_frame || escaped) errors<=errors+1'b1;
                        else if(protocol_id==0 && count==2) begin
                            buffer_available<=control_value;buffer_status_valid<=1;
                        end else if(protocol_id==1 && count>=4 &&
                                    declared_length==count && !declared_length[15]) begin
                            if(!packet_ready || packet_take) begin
                                read_bank<=write_bank;write_bank<=~write_bank;
                                packet_length<=count;packet_ready<=1;
                                if(received_packets!=16'hffff)received_packets<=received_packets+1'b1;
                            end else overruns<=overruns+1'b1;
                        end else if(count!=0 || protocol_id!=0) errors<=errors+1'b1;
                    end
                    // A closing flag can also start the next frame.
                    active<=1;escaped<=0;have_protocol<=0;bad_frame<=0;
                    count<=0;declared_length<=0;control_value<=0;
                end else if(active && !bad_frame) begin
                    if(!escaped && incoming==8'h7d) escaped<=1;
                    else begin
                        escaped<=0;
                        if(!have_protocol) begin
                            protocol_id<=unescaped;have_protocol<=1;
                            if(unescaped>1) bad_frame<=1;
                        end else if(count<512) begin
                            if(protocol_id==1) begin
                                mem[{write_bank,count[8:0]}]<=unescaped;
                                if(count==0) declared_length[7:0]<=unescaped;
                                if(count==1) begin
                                    declared_length[15:8]<=unescaped;
                                    if(unescaped[7]) bad_frame<=1;
                                end
                                if(count==2 && unescaped>5) bad_frame<=1;
                            end else begin
                                if(count==0) control_value[7:0]<=unescaped;
                                if(count==1) control_value[15:8]<=unescaped;
                                if(count>=2) bad_frame<=1;
                            end
                            count<=count+1'b1;
                        end else bad_frame<=1;
                    end
                end
            end
        end
    end
endmodule
