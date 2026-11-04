// ASCII note labels use 8px pitch with full 16px glyph height.
if(perform && label_profile==2'd0)begin
 if(local_label_x>=27 && local_label_x<43 && y>=292 && y<308)begin address=14'd10624+(local_label_x-27)/8;small_text=1;small_col=(local_label_x-27)%8+4;small_row=y-292;end
 if(local_label_x>=48 && local_label_x<64 && y>=249 && y<265)begin address=14'd10656+(local_label_x-48)/8;small_text=1;small_col=(local_label_x-48)%8+4;small_row=y-249;end
 if(local_label_x>=85 && local_label_x<101 && y>=219 && y<235)begin address=14'd10688+(local_label_x-85)/8;small_text=1;small_col=(local_label_x-85)%8+4;small_row=y-219;end
 if(local_label_x>=132 && local_label_x<148 && y>=208 && y<224)begin address=14'd10720+(local_label_x-132)/8;small_text=1;small_col=(local_label_x-132)%8+4;small_row=y-208;end
 if(local_label_x>=175 && local_label_x<199 && y>=219 && y<235)begin address=14'd10752+(local_label_x-175)/8;small_text=1;small_col=(local_label_x-175)%8+4;small_row=y-219;end
 if(local_label_x>=216 && local_label_x<232 && y>=249 && y<265)begin address=14'd10784+(local_label_x-216)/8;small_text=1;small_col=(local_label_x-216)%8+4;small_row=y-249;end
 if(local_label_x>=237 && local_label_x<253 && y>=292 && y<308)begin address=14'd10816+(local_label_x-237)/8;small_text=1;small_col=(local_label_x-237)%8+4;small_row=y-292;end
end
if(perform && label_profile==2'd1)begin
 if(local_label_x>=29 && local_label_x<45 && y>=283 && y<299)begin address=14'd10624+(local_label_x-29)/8;small_text=1;small_col=(local_label_x-29)%8+4;small_row=y-283;end
 if(local_label_x>=69 && local_label_x<85 && y>=229 && y<245)begin address=14'd10656+(local_label_x-69)/8;small_text=1;small_col=(local_label_x-69)%8+4;small_row=y-229;end
 if(local_label_x>=132 && local_label_x<148 && y>=208 && y<224)begin address=14'd10688+(local_label_x-132)/8;small_text=1;small_col=(local_label_x-132)%8+4;small_row=y-208;end
 if(local_label_x>=191 && local_label_x<215 && y>=229 && y<245)begin address=14'd10752+(local_label_x-191)/8;small_text=1;small_col=(local_label_x-191)%8+4;small_row=y-229;end
 if(local_label_x>=235 && local_label_x<251 && y>=283 && y<299)begin address=14'd10784+(local_label_x-235)/8;small_text=1;small_col=(local_label_x-235)%8+4;small_row=y-283;end
end
if(perform && label_profile==2'd2)begin
 if(local_label_x>=25 && local_label_x<41 && y>=302 && y<318)begin address=14'd10624+(local_label_x-25)/8;small_text=1;small_col=(local_label_x-25)%8+4;small_row=y-302;end
 if(local_label_x>=28 && local_label_x<52 && y>=275 && y<291)begin address=14'd10848+(local_label_x-28)/8;small_text=1;small_col=(local_label_x-28)%8+4;small_row=y-275;end
 if(local_label_x>=46 && local_label_x<62 && y>=250 && y<266)begin address=14'd10656+(local_label_x-46)/8;small_text=1;small_col=(local_label_x-46)%8+4;small_row=y-250;end
 if(local_label_x>=62 && local_label_x<86 && y>=230 && y<246)begin address=14'd10880+(local_label_x-62)/8;small_text=1;small_col=(local_label_x-62)%8+4;small_row=y-230;end
 if(local_label_x>=91 && local_label_x<107 && y>=216 && y<232)begin address=14'd10688+(local_label_x-91)/8;small_text=1;small_col=(local_label_x-91)%8+4;small_row=y-216;end
 if(local_label_x>=118 && local_label_x<134 && y>=209 && y<225)begin address=14'd10720+(local_label_x-118)/8;small_text=1;small_col=(local_label_x-118)%8+4;small_row=y-209;end
 if(local_label_x>=142 && local_label_x<166 && y>=209 && y<225)begin address=14'd10912+(local_label_x-142)/8;small_text=1;small_col=(local_label_x-142)%8+4;small_row=y-209;end
 if(local_label_x>=169 && local_label_x<193 && y>=216 && y<232)begin address=14'd10752+(local_label_x-169)/8;small_text=1;small_col=(local_label_x-169)%8+4;small_row=y-216;end
 if(local_label_x>=190 && local_label_x<222 && y>=230 && y<246)begin address=14'd10944+(local_label_x-190)/8;small_text=1;small_col=(local_label_x-190)%8+4;small_row=y-230;end
 if(local_label_x>=218 && local_label_x<234 && y>=250 && y<266)begin address=14'd10784+(local_label_x-218)/8;small_text=1;small_col=(local_label_x-218)%8+4;small_row=y-250;end
 if(local_label_x>=228 && local_label_x<252 && y>=275 && y<291)begin address=14'd10976+(local_label_x-228)/8;small_text=1;small_col=(local_label_x-228)%8+4;small_row=y-275;end
 if(local_label_x>=239 && local_label_x<255 && y>=302 && y<318)begin address=14'd10816+(local_label_x-239)/8;small_text=1;small_col=(local_label_x-239)%8+4;small_row=y-302;end
end
