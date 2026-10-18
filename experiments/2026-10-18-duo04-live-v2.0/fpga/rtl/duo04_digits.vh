function[7:0]digit_glyph;input[3:0]d;begin case(d)
0:digit_glyph=4;
1:digit_glyph=5;
2:digit_glyph=6;
3:digit_glyph=7;
4:digit_glyph=8;
5:digit_glyph=9;
6:digit_glyph=10;
7:digit_glyph=11;
8:digit_glyph=12;
9:digit_glyph=13;
default:digit_glyph=0;endcase end endfunction
