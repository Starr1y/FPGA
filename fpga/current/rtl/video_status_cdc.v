// Bundled-data request/acknowledge crossing. The source snapshot is held
// until the next frame request; destination captures only after synced ack.
module video_status_cdc #(parameter WIDTH=256)(
    input core_clk,input core_reset_n,input [WIDTH-1:0] core_status,
    input pixel_clk,input pixel_reset_n,input frame_request,
    output reg [WIDTH-1:0] pixel_status,output reg pixel_status_valid
);
    reg pixel_request,core_ack,last_ack;
    reg [1:0] request_sync;
    reg [2:0] ack_sync;
    reg [WIDTH-1:0] held_status;
    always @(posedge core_clk) begin
        if(!core_reset_n) begin request_sync<=0;core_ack<=0;held_status<=0;end
        else begin
            request_sync<={request_sync[0],pixel_request};
            if(request_sync[1]!=core_ack) begin held_status<=core_status;core_ack<=request_sync[1];end
        end
    end
    always @(posedge pixel_clk) begin
        if(!pixel_reset_n) begin pixel_request<=0;ack_sync<=0;last_ack<=0;pixel_status<=0;pixel_status_valid<=0;end
        else begin
            pixel_status_valid<=0;
            ack_sync<={ack_sync[1:0],core_ack};
            if(frame_request && pixel_request==ack_sync[2]) pixel_request<=!pixel_request;
            if(ack_sync[2]!=last_ack) begin pixel_status<=held_status;last_ack<=ack_sync[2];pixel_status_valid<=1;end
        end
    end
endmodule
