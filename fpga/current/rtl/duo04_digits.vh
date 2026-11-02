function[8:0]digit_glyph;input[3:0]d;begin case(d)
0:digit_glyph=6;
1:digit_glyph=7;
2:digit_glyph=8;
3:digit_glyph=9;
4:digit_glyph=10;
5:digit_glyph=11;
6:digit_glyph=12;
7:digit_glyph=13;
8:digit_glyph=14;
9:digit_glyph=15;
default:digit_glyph=0;endcase end endfunction
