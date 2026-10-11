`timescale 1ns/1ps
module tb_dual_note_map;
 reg[1:0]profile=0,member=0;reg[3:0]zone=0;reg signed[1:0]octave=0;reg chord=0;
 wire valid;wire[6:0]note;integer diatonic[0:6],pentatonic[0:4],expected,count;
 dual_note_map dut(profile,zone,octave,chord,member,valid,note);
 initial begin
  diatonic[0]=0;diatonic[1]=2;diatonic[2]=4;diatonic[3]=5;diatonic[4]=7;diatonic[5]=9;diatonic[6]=11;
  pentatonic[0]=0;pentatonic[1]=2;pentatonic[2]=4;pentatonic[3]=7;pentatonic[4]=9;
  count=0;
  for(integer p=0;p<4;p++)for(integer z=0;z<16;z++)for(integer o=-2;o<=1;o++)for(integer c=0;c<2;c++)for(integer m=0;m<4;m++)begin
   profile=p;zone=z;octave=o;chord=c;member=m;#1;
   if(p==3 || z>=(p==1 ? 5 : p==2 ? 12 : 7) || (c && m==3))begin
    if(valid)$fatal(1,"invalid layout accepted");
   end else begin
    if(p==0)expected=60+diatonic[(z+(c ? 2*m : 0))%7]+12*((z+(c ? 2*m : 0))/7)+12*o;
    else expected=60+(p==1 ? pentatonic[z] : z)+12*o+(c ? m==1 ? 4 : m==2 ? 7 : 0 : 0);
    if(!valid || note!=expected)$fatal(1,"mapping p%0d z%0d o%0d c%0d m%0d expected%0d got%0d",p,z,o,c,m,expected,note);
   end
   count++;
  end
  $display("TB_PASS %0d exhaustive 7/5/12 mapping vectors, octave offsets, diatonic/major triads and invalid layouts",count);$finish;
 end
endmodule
