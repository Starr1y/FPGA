// 48 kHz initial presets. 0 pluck, 1 bass, 2 wind, 3 bell.
// Release coefficient is Q0.16; the audio core also enforces exact tail duration.
module timbre_presets(input [1:0] preset_id,release_id,
    output reg [1:0] waveform,output reg [15:0] attack,decay,sustain,release_coefficient);
    always @* begin
        waveform=3;
        case(preset_id)
            0:begin attack=341;decay=10;sustain=0;end
            1:begin attack=455;decay=20;sustain=24576;end
            2:begin attack=46;decay=8;sustain=49152;end
            3:begin attack=1365;decay=2;sustain=0;end
        endcase
        case(release_id)
            0:release_coefficient=47; // ~ -60 dB at 200 ms
            1:release_coefficient=19; // ~ -60 dB at 500 ms
            default:release_coefficient=6; // ~ -60 dB at 1.5 s
        endcase
    end
endmodule
