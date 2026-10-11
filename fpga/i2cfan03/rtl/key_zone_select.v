// Tang Mega 138K Dock USER_BUTTON1/2: pulled high, pressed low.
// One move per press after 20 ms debounce; no auto-repeat while held.
module key_zone_select #(
    parameter integer DEBOUNCE_TICKS = 1000000
)(
    input clk, input rst_n,
    input key1_n, input key2_n,
    output reg [2:0] selected_zone
);
    reg [1:0] key1_sync, key2_sync;
    reg key1_stable, key2_stable;
    reg [19:0] key1_count, key2_count;
    wire key1_press = (key1_sync[1] != key1_stable) &&
                      (key1_count == DEBOUNCE_TICKS-1) && !key1_sync[1];
    wire key2_press = (key2_sync[1] != key2_stable) &&
                      (key2_count == DEBOUNCE_TICKS-1) && !key2_sync[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            key1_sync <= 2'b11;
            key2_sync <= 2'b11;
            key1_stable <= 1'b1;
            key2_stable <= 1'b1;
            key1_count <= 0;
            key2_count <= 0;
            selected_zone <= 3'd3; // Fa: center of Do..Si
        end else begin
            key1_sync <= {key1_sync[0], key1_n};
            key2_sync <= {key2_sync[0], key2_n};
            if (key1_sync[1] == key1_stable) key1_count <= 0;
            else if (key1_count == DEBOUNCE_TICKS-1) begin
                key1_stable <= key1_sync[1];
                key1_count <= 0;
            end else key1_count <= key1_count + 1'b1;

            if (key2_sync[1] == key2_stable) key2_count <= 0;
            else if (key2_count == DEBOUNCE_TICKS-1) begin
                key2_stable <= key2_sync[1];
                key2_count <= 0;
            end else key2_count <= key2_count + 1'b1;

            if (key1_press && key2_sync[1] && selected_zone != 0)
                selected_zone <= selected_zone - 1'b1;
            else if (key2_press && key1_sync[1] && selected_zone != 6)
                selected_zone <= selected_zone + 1'b1;
        end
    end
endmodule
