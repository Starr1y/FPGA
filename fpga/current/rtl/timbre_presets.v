// DUO04 stable IDs: piano, marimba, electric piano, plucked string.
module timbre_presets(input[2:0]preset_id,input[1:0]release_id,
 output reg[1:0]waveform,output reg[15:0]attack,decay,sustain,release_coefficient);
 always @*begin
  waveform=0;attack=683;decay=68;sustain=49152;
  case(preset_id)
   1:begin attack=2731;decay=137;sustain=57344;end
   2:begin attack=455;decay=34;sustain=49152;end
   3:begin attack=1365;decay=68;sustain=57344;end
   default:begin end
  endcase
  case(release_id)0:release_coefficient=47;1:release_coefficient=19;default:release_coefficient=6;endcase
 end
endmodule
