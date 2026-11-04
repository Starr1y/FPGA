// Shared between menu control and HDMI labels: one authoritative ordering.
function[3:0]count;input[2:0]g;begin case(g)0:count=5;1:count=4;2:count=2;3:count=6;4:count=3;default:count=4;endcase end endfunction
function[5:0]field_at;input[2:0]g;input[3:0]n;
begin case(g)
0:case(n)0:field_at=1;1:field_at=7;2:field_at=3;3:field_at=11;default:field_at=13;endcase
1:case(n)0:field_at=2;1:field_at=4;2:field_at=12;default:field_at=14;endcase
2:field_at=n==0 ? 9 : 10;
3:case(n)0:field_at=31;1:field_at=32;2:field_at=15;3:field_at=16;4:field_at=17;default:field_at=18;endcase
4:field_at=n==0 ? 19 : n==1 ? 23 : 27;
default:case(n)0:field_at=0;1:field_at=8;2:field_at=21;default:field_at=28;endcase
endcase end endfunction
