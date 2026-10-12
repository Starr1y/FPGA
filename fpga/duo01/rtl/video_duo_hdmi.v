// 640x480 digital video output for Tang Mega 138K Dock C HDMI connector.
// Uses the board's 50 MHz reference. One Gowin PLL generates a 125 MHz
// serializer clock and a 25 MHz pixel clock (640x480 at 59.52 Hz).
module video_duo_hdmi(
    input clk50, input rst_n,
    input [767:0] performance_status,
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

    wire clocks_ready = rst_n && pll_lock;
    reg [2:0] pixel_reset_pipe = 0;
    wire pixel_reset_n = pixel_reset_pipe[2];
    always @(posedge pixel_clk or negedge clocks_ready) begin
        if (!clocks_ready) pixel_reset_pipe <= 0;
        else pixel_reset_pipe <= {pixel_reset_pipe[1:0],1'b1};
    end
    wire [7:0] red, green, blue;
    wire hsync, vsync, de,frame_request;
    wire [767:0] pixel_status;wire pixel_status_valid;
    video_status_cdc #(.WIDTH(768)) status_cdc(.core_clk(clk50),.core_reset_n(rst_n),.core_status(performance_status),
        .pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),.frame_request(frame_request),.pixel_status(pixel_status),.pixel_status_valid(pixel_status_valid));
    duo_panel panel(.clk(pixel_clk),.rst_n(pixel_reset_n),.status(pixel_status),.status_update(pixel_status_valid),
      .frame_request(frame_request),.red(red),.green(green),.blue(blue),.hsync(hsync),.vsync(vsync),.de(de));
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
