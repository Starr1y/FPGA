// MIDI C4 baseline. Profile 0 diatonic, 1 major pentatonic, 2 chromatic.
// Chord mode snapshots a diatonic triad for profile 0, a major triad otherwise.
module dual_note_map(input [1:0]profile,input[3:0]zone,
 input signed[1:0]octave,input chord,input[1:0]member,
 output reg valid,output reg[6:0]midi_note);
 // Bounded LUT avoids 32-bit divide/modulo in the allocation control path.
 reg[4:0]degree;reg[5:0]offset;reg[6:0]base;
 always @*begin
  valid=profile<3 && zone<(profile==1 ? 5 : profile==2 ? 12 : 7) && (!chord || member<3);
  degree={1'b0,zone}+(chord ? {2'b0,member,1'b0} : 5'd0);
  case(octave)2'b10:base=36;2'b11:base=48;2'b00:base=60;default:base=72;endcase
  offset=0;
  case(profile)
   0:case(degree)
    0:offset=0;1:offset=2;2:offset=4;3:offset=5;4:offset=7;5:offset=9;6:offset=11;
    7:offset=12;8:offset=14;9:offset=16;10:offset=17;11:offset=19;12:offset=21;13:offset=23;
    14:offset=24;15:offset=26;16:offset=28;17:offset=29;18:offset=31;19:offset=33;20:offset=35;
    default:offset=36;
   endcase
   1:begin case(zone)0:offset=0;1:offset=2;2:offset=4;3:offset=7;default:offset=9;endcase
    if(chord)offset=offset+(member==1 ? 6'd4 : member==2 ? 6'd7 : 6'd0);end
   2:offset={2'b0,zone}+(chord ? member==1 ? 6'd4 : member==2 ? 6'd7 : 6'd0 : 6'd0);
   default:offset=0;
  endcase
  // All valid combinations lie within MIDI 36..89.
  midi_note=base+{1'b0,offset};
 end
endmodule
