// MIDI C4 baseline. Profile 0 diatonic, 1 major pentatonic, 2 chromatic.
// Chord mode snapshots a diatonic triad for profile 0, a major triad otherwise.
module dual_note_map(input [1:0]profile,input[3:0]zone,
 input signed[1:0]octave,input chord,input[1:0]member,
 output reg valid,output reg[6:0]midi_note);
 function integer degree;
 input integer d;
 begin case(d%7)0:degree=0;1:degree=2;2:degree=4;3:degree=5;4:degree=7;5:degree=9;default:degree=11;endcase
 degree=degree+(d/7)*12;end
 endfunction
 integer offset,n;
 always @*begin
  valid=profile<3 && zone<(profile==1 ? 5 : profile==2 ? 12 : 7) && (!chord || member<3);
  offset=0;
  case(profile)
   0:offset=degree(zone+(chord ? member*2 : 0));
   1:begin case(zone)0:offset=0;1:offset=2;2:offset=4;3:offset=7;default:offset=9;endcase
    if(chord)offset=offset+(member==1 ? 4 : member==2 ? 7 : 0);end
   2:offset=zone+(chord ? member==1 ? 4 : member==2 ? 7 : 0 : 0);
   default:offset=0;
  endcase
  n=60+offset+$signed(octave)*12;
  midi_note=n[6:0];if(n<0 || n>127)valid=0;
 end
endmodule
