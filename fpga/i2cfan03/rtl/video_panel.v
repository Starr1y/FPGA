// Retro-futuristic TangLab status screen with live key-selected note zone.
// 640x480 active, 800x525 total, 59.52 Hz with a 25 MHz pixel clock.
module video_panel(
    input clk, input rst_n,
    input [39:0] levels, input signed [7:0] mix_sample,
    input [6:0] active_zones, input [2:0] selected_zone,
    input sample_update,
    output reg [7:0] red, green, blue,
    output hsync, vsync, de
);
    reg [9:0] x=0, y=0;
    reg [4:0] heartbeat_count=0;
    reg heartbeat=0;
    always @(posedge clk) begin
        if (!rst_n) begin x<=0; y<=0; heartbeat_count<=0; heartbeat<=0; end
        else if (x==799) begin
            x<=0;
            y <= (y==524) ? 0 : y+1'b1;
            if (y==524) begin
                if (heartbeat_count==29) begin
                    heartbeat_count<=0;
                    heartbeat<=~heartbeat;
                end else heartbeat_count<=heartbeat_count+1'b1;
            end
        end
        else x<=x+1'b1;
    end
    assign de = x<640 && y<480;
    assign hsync = !(x>=656 && x<752);
    assign vsync = !(y>=490 && y<492);

    reg signed [7:0] history [0:127];
    reg [6:0] write_ptr=0;
    reg [7:0] written=0;
    always @(posedge clk) begin
        if (!rst_n) begin write_ptr<=0; written<=0; end
        else if (sample_update) begin
            history[write_ptr] <= mix_sample;
            write_ptr <= write_ptr + 1'b1;
            if (!written[7]) written <= written + 1'b1;
        end
    end
    wire [6:0] wave_addr = write_ptr + ((x-10'd304) >> 1);
    wire signed [7:0] wave_val = history[wave_addr];
    wire signed [10:0] wave_y = 11'sd225 - ($signed(wave_val) >>> 1);
    wire signed [10:0] sy = $signed({1'b0,y});
    wire wave_core = written[7] && x>=304 && x<560 &&
                     sy>=wave_y-1 && sy<=wave_y+1;
    wire wave_glow = written[7] && x>=304 && x<560 &&
                     sy>=wave_y-4 && sy<=wave_y+4;

    function [7:0] label_char;
        input [3:0] id;
        input [3:0] pos;
        input [2:0] number;
        begin
            label_char = " ";
            case (id)
            0: case(pos)
                0:label_char="T";1:label_char="A";2:label_char="N";
                3:label_char="G";4:label_char="L";5:label_char="A";
                6:label_char="B";endcase
            1: case(pos)
                0:label_char="F";1:label_char="P";2:label_char="G";
                3:label_char="A";5:label_char="L";6:label_char="I";
                7:label_char="V";8:label_char="E";endcase
            2: case(pos)
                0:label_char="V";1:label_char="O";2:label_char="I";
                3:label_char="C";4:label_char="E";
                6:label_char="0"+number;endcase
            3: case(pos)
                0:label_char="M";1:label_char="I";2:label_char="X";
                4:label_char="/";6:label_char="L";7:label_char="I";
                8:label_char="V";9:label_char="E";endcase
            4: case(pos)
                0:label_char="I";1:label_char="2";2:label_char="S";
                4:label_char="O";5:label_char="U";6:label_char="T";
                7:label_char="P";8:label_char="U";9:label_char="T";endcase
            5: case(pos)
                0:label_char="4";1:label_char="8";
                3:label_char="K";4:label_char="H";5:label_char="Z";endcase
            6: case(pos)
                0:label_char="4";2:label_char="V";3:label_char="O";
                4:label_char="I";5:label_char="C";6:label_char="E";
                7:label_char="S";endcase
            7: case(pos)
                0:label_char="N";1:label_char="O";2:label_char="T";
                3:label_char="E";5:label_char="Z";6:label_char="O";
                7:label_char="N";8:label_char="E";9:label_char="S";endcase
            8: case(pos)
                0:label_char="K";1:label_char="E";2:label_char="Y";
                4:label_char="S";5:label_char="E";6:label_char="L";
                7:label_char="E";8:label_char="C";9:label_char="T";endcase
            endcase
        end
    endfunction

    function [7:0] zone_char;
        input [2:0] id;
        input [1:0] pos;
        begin
            zone_char=" ";
            case(id)
             0:case(pos) 0:zone_char="D";1:zone_char="O";endcase
             1:case(pos) 0:zone_char="R";1:zone_char="E";endcase
             2:case(pos) 0:zone_char="M";1:zone_char="I";endcase
             3:case(pos) 0:zone_char="F";1:zone_char="A";endcase
             4:case(pos) 0:zone_char="S";1:zone_char="O";2:zone_char="L";endcase
             5:case(pos) 0:zone_char="L";1:zone_char="A";endcase
             6:case(pos) 0:zone_char="S";1:zone_char="I";endcase
            endcase
        end
    endfunction

    reg [7:0] font_ch;
    reg [3:0] font_row;
    reg [2:0] font_col;
    reg [1:0] font_color; // 1 cyan, 2 magenta
    reg [2:0] voice_num;
    wire zone_area = x>=47 && x<593 && y>=399 && y<439;
    wire [2:0] zone_index = (x-10'd47)/78;
    wire [6:0] zone_offset = (x-10'd47)%78;
    wire zone_key = zone_area && zone_offset<76;
    wire zone_lit = zone_key && active_zones[zone_index];
    wire zone_selected = zone_key && zone_index==selected_zone;
    wire selected_marker = x>=47 && x<593 && y>=391 && y<396 &&
                           zone_offset<76 && zone_index==selected_zone;
    wire [7:0] font_bits;
    video_font font(.ch(font_ch), .row(font_row), .bits(font_bits));
    wire font_hit = font_bits[7-font_col];
    always @* begin
        font_ch=" "; font_row=0; font_col=0; font_color=0; voice_num=0;
        if (x>=40 && x<152 && y>=30 && y<54) begin
            font_ch=label_char(0,(x-40)>>4,0);
            font_row=(y-30)>>1; font_col=(x-40)>>1; font_color=2;
        end else if (x>=488 && x<568 && y>=42 && y<54) begin
            font_ch=label_char(1,(x-488)>>3,0);
            font_row=y-42; font_col=x-488; font_color=1;
        end else if (x>=46 && x<110 && y>=111 && y<123) begin
            font_ch=label_char(6,(x-46)>>3,0);
            font_row=y-111; font_col=x-46; font_color=1;
        end else if (x>=292 && x<372 && y>=111 && y<123) begin
            font_ch=label_char(3,(x-292)>>3,0);
            font_row=y-111; font_col=x-292; font_color=2;
        end else if (x>=43 && x<99 && y>=153 && y<309 &&
                     ((y-153)%48)<12) begin
            voice_num=((y-153)/48)+1;
            font_ch=label_char(2,(x-43)>>3,voice_num);
            font_row=(y-153)%48; font_col=x-43;
            font_color=voice_num[0] ? 1 : 2;
        end else if (x>=43 && x<123 && y>=373 && y<385) begin
            font_ch=label_char(7,(x-43)>>3,0);
            font_row=y-373; font_col=x-43; font_color=1;
        end else if (x>=488 && x<568 && y>=373 && y<385) begin
            font_ch=label_char(8,(x-488)>>3,0);
            font_row=y-373; font_col=x-488; font_color=2;
        end else if (zone_key && zone_offset>=14 && zone_offset<62 && y>=410 && y<426) begin
            font_ch=zone_char(zone_index,(zone_offset-14)>>4);
            font_row=(y-410)>>1; font_col=(zone_offset-14)>>1;
            font_color=active_zones[zone_index] ? 3 : 1;
        end
        font_col=font_col[2:0];
    end

    wire [1:0] lane = (y-10'd140)/48;
    wire [7:0] level = levels[lane*8+:8];
    wire meter_track = x>=125 && x<245 && y>=143 && y<323 &&
                       ((y-143)%48)<20;
    wire meter_fill = meter_track && x-125 < level;
    wire meter_peak = meter_track && x-125 == level;
    wire scope = x>=282 && x<604 && y>=135 && y<334;
    wire bottom = x>=28 && x<612 && y>=360 && y<451;
    wire grid = ((x[4:0]==0) || (y[4:0]==0));

    // All colors are fixed hardware tokens: #0A0014, #FF006E and #00FFFF.
    always @* begin
        {red,green,blue}=24'h0A0014;
        if (de) begin
            if (x>=28 && x<612 && y>=101 && y<347)
                {red,green,blue}=y[1:0]==0 ? 24'h0D0620 : 24'h120826;
            if (scope && grid) {red,green,blue}=24'h23103A;
            if (bottom) {red,green,blue}=y[1:0]==0 ? 24'h0B041B : 24'h10071E;
            if (zone_key) {red,green,blue}=24'h1A1330;
            if (zone_selected) {red,green,blue}=24'h0C3A45;
            if (zone_lit) {red,green,blue}=24'hFF006E;
            if (zone_key && (y==399 || y==438)) {red,green,blue}=zone_selected ? 24'h00FFFF : zone_lit ? 24'hFFD8F0 : 24'h275A62;
            if (zone_key && (zone_offset==0 || zone_offset==75)) {red,green,blue}=zone_selected ? 24'h00FFFF : zone_lit ? 24'hFFD8F0 : 24'h275A62;
            if (selected_marker) {red,green,blue}=24'h00FFFF;
            if (y==83 && x>=28 && x<612) {red,green,blue}=24'hFF006E;
            if (x>=588 && x<600 && y>=42 && y<54)
                {red,green,blue}=heartbeat ? 24'h00FFFF : 24'h15404A;
            if ((x==28 || x==611) && y>=101 && y<347)
                {red,green,blue}=24'h6D145A;
            if ((y==101 || y==346) && x>=28 && x<612)
                {red,green,blue}=24'h6D145A;
            if (x==269 && y>=115 && y<333) {red,green,blue}=24'h00FFFF;
            if (y==225 && x>=289 && x<597) {red,green,blue}=24'h164C57;
            if (meter_track) {red,green,blue}=24'h271437;
            if (meter_fill) {red,green,blue}=lane[0] ? 24'hFF006E : 24'h00FFFF;
            if (meter_peak) {red,green,blue}=24'hFFD8F0;
            if (scope && wave_glow) {red,green,blue}=24'h76205A;
            if (scope && wave_core) {red,green,blue}=24'hFF006E;
            if ((x==28 || x==611) && y>=360 && y<451)
                {red,green,blue}=24'h233B50;
            if ((y==360 || y==450) && x>=28 && x<612)
                {red,green,blue}=24'h233B50;
            if (font_color!=0 && font_hit)
                {red,green,blue}=font_color==1 ? 24'h00FFFF : font_color==2 ? 24'hFF006E : 24'h0A0014;
        end else {red,green,blue}=24'h000000;
    end
endmodule
