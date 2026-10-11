// 640x480 digital video output for Tang Mega 138K Dock C HDMI connector.
// Uses the board's 50 MHz reference. One Gowin PLL generates a 125 MHz
// serializer clock and a 25 MHz pixel clock (640x480 at 59.52 Hz).
module video_hdmi(
    input clk50, input rst_n,
    input [79:0] samples, input sample_valid,
    input [1023:0] performance_status,
    output tmds_clk_p, output tmds_clk_n,
    output [2:0] tmds_d_p, output [2:0] tmds_d_n
);
`ifdef TANG_SIM
    // Existing UART/audio benches can run without Gowin device primitives.
    assign tmds_clk_p = 1'b0;
    assign tmds_clk_n = 1'b1;
    assign tmds_d_p = 3'b000;
    assign tmds_d_n = 3'b111;
`else
    wire clk5, pixel_clk, pll_lock;
    video_pll_125 pll_ser(.lock(pll_lock), .clkout0(clk5),
                          .clkout1(pixel_clk), .clkin(clk50));

    // Audio samples stay stable for >20 us. Synchronize their update event,
    // then capture the held bus in the pixel domain.
    reg [39:0] held_levels = 0;
    reg [7:0] held_mix = 0;
    reg audio_toggle = 0;
    reg [7:0] peak [0:4];
    reg [8:0] decay_count = 0;
    integer i;
    reg [15:0] signed_sample;
    reg [7:0] magnitude;
    always @(posedge clk50) begin
        if (!rst_n) begin
            held_levels <= 0;
            held_mix <= 0;
            audio_toggle <= 0;
            decay_count <= 0;
            for (i=0; i<5; i=i+1) peak[i] <= 0;
        end else if (sample_valid) begin
            if (decay_count==479) decay_count<=0;
            else decay_count<=decay_count+1'b1;
            for (i=0; i<5; i=i+1) begin
                signed_sample = samples[i*16+:16];
                magnitude = signed_sample[15] ?
                    (~signed_sample[15:8] + 1'b1) : signed_sample[15:8];
                if (magnitude>peak[i]) peak[i]<=magnitude;
                else if (decay_count==479 && peak[i]!=0) peak[i]<=peak[i]-1'b1;
                held_levels[i*8+:8] <= peak[i];
            end
            held_mix <= samples[79:72];
            audio_toggle <= ~audio_toggle;
        end
    end
    reg [2:0] update_sync = 0;
    reg [39:0] levels = 0;
    reg signed [7:0] mix_sample = 0;
    wire clocks_ready = rst_n && pll_lock;
    reg [2:0] pixel_reset_pipe = 0;
    wire pixel_reset_n = pixel_reset_pipe[2];
    always @(posedge pixel_clk or negedge clocks_ready) begin
        if (!clocks_ready) pixel_reset_pipe <= 0;
        else pixel_reset_pipe <= {pixel_reset_pipe[1:0],1'b1};
    end
    always @(posedge pixel_clk) begin
        if (!pixel_reset_n) begin
            update_sync <= 0;
            levels <= 0;
            mix_sample <= 0;
        end else begin
            update_sync <= {update_sync[1:0], audio_toggle};
            if (update_sync[2] != update_sync[1]) begin
                levels <= held_levels;
                mix_sample <= held_mix;
            end
        end
    end

    wire [7:0] red, green, blue;
    wire hsync, vsync, de,frame_request;
    wire [1023:0] pixel_status;wire pixel_status_valid;
    video_status_cdc #(.WIDTH(1024)) status_cdc(.core_clk(clk50),.core_reset_n(rst_n),.core_status(performance_status),
        .pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),.frame_request(frame_request),.pixel_status(pixel_status),.pixel_status_valid(pixel_status_valid));
    video_instrument_panel #(.SAFE_LAYOUT(1)) panel(.clk(pixel_clk), .rst_n(pixel_reset_n),
                      .levels(levels), .mix_sample(mix_sample),
                      .performance_status(pixel_status),.status_update(pixel_status_valid),.frame_request(frame_request),
                      .sample_update(update_sync[2] != update_sync[1]),
                      .red(red), .green(green), .blue(blue),
                      .hsync(hsync), .vsync(vsync), .de(de));
    // Separate procedural pixel/font work from TMDS encoding. Delay RGB and
    // all blanking/sync controls together so the raster is unchanged.
    reg [23:0] rgb_pixel;
    reg rgb_de,rgb_hsync,rgb_vsync;
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin rgb_pixel<=0;rgb_de<=0;rgb_hsync<=1;rgb_vsync<=1;end
        else begin rgb_pixel<={red,green,blue};rgb_de<=de;rgb_hsync<=hsync;rgb_vsync<=vsync;end
    end
    wire [9:0] tmds_word [0:2];
    svo_tmds enc_b(.clk(pixel_clk), .resetn(pixel_reset_n), .de(rgb_de),
                   .ctrl({rgb_vsync,rgb_hsync}), .din(rgb_pixel[7:0]), .dout(tmds_word[0]));
    svo_tmds enc_g(.clk(pixel_clk), .resetn(pixel_reset_n), .de(rgb_de),
                   .ctrl(2'b00), .din(rgb_pixel[15:8]), .dout(tmds_word[1]));
    svo_tmds enc_r(.clk(pixel_clk), .resetn(pixel_reset_n), .de(rgb_de),
                   .ctrl(2'b00), .din(rgb_pixel[23:16]), .dout(tmds_word[2]));

    wire [2:0] serial;
    genvar lane;
    generate for (lane=0; lane<3; lane=lane+1) begin: tx
        OSER10 serializer(
            .Q(serial[lane]),
            .D0(tmds_word[lane][0]), .D1(tmds_word[lane][1]),
            .D2(tmds_word[lane][2]), .D3(tmds_word[lane][3]),
            .D4(tmds_word[lane][4]), .D5(tmds_word[lane][5]),
            .D6(tmds_word[lane][6]), .D7(tmds_word[lane][7]),
            .D8(tmds_word[lane][8]), .D9(tmds_word[lane][9]),
            // After configuration, the encoder supplies valid words before
            // a display can acquire sync. Avoid an asynchronous reset crossing.
            .PCLK(pixel_clk), .FCLK(clk5), .RESET(1'b0));
        ELVDS_OBUF outbuf(.I(serial[lane]), .O(tmds_d_p[lane]),
                          .OB(tmds_d_n[lane]));
    end endgenerate
    ELVDS_OBUF clockbuf(.I(pixel_clk), .O(tmds_clk_p), .OB(tmds_clk_n));
`endif
endmodule
