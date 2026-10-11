// Two synchronous ROM reads. Fourier tables contain one oscillator cycle.
// Select a conservative harmonic cap from the normalized FTW; no floats in RTL.
module instrument_waves(input clk,input [31:0] phase,frequency,input bass,input [7:0] brightness,
    output reg signed [15:0] dark,bright,output reg [15:0] blend_gain);
    reg [15:0] dark_rom[0:3071],bright_rom[0:1535];
    reg [15:0] gain_rom[0:3071];
    reg [2:0] band;
    wire [11:0] dark_address={1'b0,band,phase[31:24]}+(bass ? 12'd1536 : 12'd0);
    wire [7:0] bright_phase=phase[31:24]+(bass ? 8'd0 : 8'd64);
    wire [10:0] bright_address={band,bright_phase};
    wire [11:0] gain_address={1'b0,band,brightness}+(bass ? 12'd1536 : 12'd0);
    initial begin
        $readmemh("rtl/instrument_dark.hex",dark_rom);
        $readmemh("rtl/instrument_bright.hex",bright_rom);
        $readmemh("rtl/instrument_gain.hex",gain_rom);
    end
    always @* begin
        if(frequency<32'd33554432) band=0;
        else if(frequency<32'd67108864) band=1;
        else if(frequency<32'd134217728) band=2;
        else if(frequency<32'd268435456) band=3;
        else if(frequency<32'd536870912) band=4;
        else band=5;
    end
    always @(posedge clk) begin
        dark<=dark_rom[dark_address];
        bright<=bass ? -$signed(bright_rom[bright_address]) : $signed(bright_rom[bright_address]);
        blend_gain<=gain_rom[gain_address];
    end
endmodule
