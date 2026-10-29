// All inputs emit semantic edits to the single top-level parameter bank.
module duo04_menu(input clk,rst_n,step,direction,short_press,long_press,
 input[11:0]keys,input remote_valid,input[3:0]remote_action,
 input running,input[1:0]mode,input teaching_active,finished,
 input[3:0]profiles,input[5:0]presets,input[8:0]volume,input[15:0]current_value,
 output[1:0]page,output reg[5:0]field,output editing,
 output reg write,output reg[15:0]value,output reg active_hand,
 output reg[2:0]level,group_id,output reg[3:0]item,output reg stop,output reg[7:0]notice,output reg[15:0]serial);
 reg edit_pending,edit_increase;reg[5:0]edit_field_q;
 reg[15:0]edit_current_q,edit_min_q,edit_max_q,edit_inc_q,edit_upper_q,edit_lower_q;
 reg diagnostic;reg[3:0]action;reg valid_action;
 assign page=level!=0 ? 1 : diagnostic ? 3 : mode==2 ? 2 : 0;
 assign editing=level==4;
 function[3:0]count;input[2:0]g;begin case(g)0,1:count=5;2:count=2;3:count=9;4:count=3;default:count=4;endcase end endfunction
 function[5:0]field_at;input[2:0]g;input[3:0]n;
 begin case(g)
 0:case(n)0:field_at=1;1:field_at=3;2:field_at=5;3:field_at=11;default:field_at=13;endcase
 1:case(n)0:field_at=2;1:field_at=4;2:field_at=6;3:field_at=12;default:field_at=14;endcase
 2:field_at=n==0 ? 9 : 10;
 3:case(n)0:field_at=7;1:field_at=29;2:field_at=30;3:field_at=31;4:field_at=32;5:field_at=15;6:field_at=16;7:field_at=17;default:field_at=18;endcase
 4:field_at=n==0 ? 19 : n==1 ? 23 : 27;
 default:case(n)0:field_at=0;1:field_at=8;2:field_at=21;default:field_at=28;endcase
 endcase end endfunction
 reg[15:0]minimum,maximum,increment,upper_start,lower_start;
 always @*begin
  minimum=0;maximum=1;increment=1;upper_start=0;lower_start=1;
  case(field)
   0,3,4,13,14,19:begin maximum=2;upper_start=1;end
   27:begin maximum=4;upper_start=3;end
   1,2,5,6,9:begin maximum=3;upper_start=2;end
   8:begin maximum=256;increment=4;upper_start=252;lower_start=4;end
   10:begin maximum=255;increment=8;upper_start=247;lower_start=8;end
   11,12:begin minimum=100;maximum=10000;increment=100;upper_start=9900;lower_start=200;end
   default:begin end
  endcase
  // These thresholds depend only on field (constants after synthesis).
  // Compare before the add/subtract rather than feeding a 16-bit adder into
  // a second 16-bit comparator on every menu edit.
  // Saturation thresholds are literal constants, no field-driven arithmetic.
  action=0;valid_action=1;
  if(keys[11] || (remote_valid && remote_action==11))action=11;
  else if(keys[9])action=9;else if(keys[10])action=10;
  else if(keys[4])action=4;else if(keys[5])action=5;
  else if(keys[6])action=6;else if(keys[7])action=7;else if(keys[8])action=8;
  else if(remote_valid)action=remote_action;
  else if(long_press)action=3;else if(short_press)action=2;
  else if(step)action=direction ? 1 : 0;else valid_action=0;
 end
 always @(posedge clk)begin
  if(!rst_n)begin edit_pending<=0;edit_increase<=0;edit_field_q<=0;edit_current_q<=0;edit_min_q<=0;edit_max_q<=0;edit_inc_q<=0;edit_upper_q<=0;edit_lower_q<=0;level<=0;group_id<=0;item<=0;field<=0;active_hand<=0;diagnostic<=0;write<=0;value<=0;stop<=0;notice<=0;serial<=0;end
  else begin
   write<=0;stop<=0;edit_pending<=0;
   // Snapshot the field-selected input first, then compare/add next clock.
   // STOP and navigation cancel an in-flight edit; they can never replay it.
   if(edit_pending && level==4 && field==edit_field_q &&
      !(teaching_active && (field==3 || field==4 || field==5 || field==6 || field==7)) &&
      !(valid_action && !(action==0 || action==1 || action==6 || action==7)))begin
    value<=edit_increase ? (edit_current_q>=edit_upper_q ? edit_max_q : edit_current_q+edit_inc_q) :
       (edit_current_q<=edit_lower_q ? edit_min_q : edit_current_q-edit_inc_q);
    write<=1;
   end
   if(valid_action)begin
    serial<=serial+1'b1;notice<=0;
    if(action==11)begin stop<=1;level<=0;notice<=1;end
    else if(action==9)begin level<=level==0 ? 2 : 0;group_id<=active_hand;item<=0;end
    else if(action==10)begin diagnostic<=!diagnostic;level<=0;end
    else if(action==3 || (level!=0 && action==5))begin
     if(level==4 || level==5)level<=3;
     else if(level==3)begin level<=2;item<=group_id;end
     else level<=0;
    end else if(level==0)begin
     case(action)
      0,1:begin field<=8;value<=action==1 ? (volume>=252 ? 256 : volume+9'd4) : (volume<=4 ? 0 : volume-9'd4);write<=1;notice<=2;end
      2:begin level<=1;item<=0;end
      4:begin field<=25;value<={15'b0,active_hand};write<=1;end
      5:if(teaching_active)notice<=3;else begin field<=active_hand ? 4 : 3;value<=profiles[active_hand*2+:2]==2 ? 0 : profiles[active_hand*2+:2]+2'd1;write<=1;end
      6:begin field<=active_hand ? 2 : 1;value<=presets[active_hand*3+:3]==3 ? 0 : presets[active_hand*3+:3]+3'd1;write<=1;end
      7:active_hand<=!active_hand;
      8:begin level<=3;group_id<=active_hand;item<=0;field<=active_hand ? 2 : 1;end
      default:begin end
     endcase
    end else if(action==0 || action==1 || action==6 || action==7)begin
     if(level==4)begin
      if(teaching_active && (field==3 || field==4 || field==5 || field==6 || field==7))notice<=3;
      else begin
       edit_pending<=1;edit_field_q<=field;edit_increase<=action==1 || action==6;
       edit_current_q<=current_value;edit_min_q<=minimum;edit_max_q<=maximum;
       edit_inc_q<=increment;edit_upper_q<=upper_start;edit_lower_q<=lower_start;
      end
     end else if(level==1 || level==2 || level==3)begin
      if(action==1 || action==6)begin
       if(item+1 >= (level==1 ? 5 : level==2 ? 6 : count(group_id)))item<=0;else item<=item+1'b1;
       if(level==3)field<=field_at(group_id,item+1>=count(group_id) ? 0 : item+1'b1);
      end else begin
       if(item==0)item<=(level==1 ? 5 : level==2 ? 6 : count(group_id))-1'b1;else item<=item-1'b1;
       if(level==3)field<=field_at(group_id,item==0 ? count(group_id)-1'b1 : item-1'b1);
      end
     end
    end else if(action==2 || action==4)begin
     case(level)
      1:case(item)
       0:begin field<=mode==2 && finished ? 27 : 22;value<=mode==2 && finished ? 4 : !running;write<=1;level<=0;end
       1:begin field<=0;value<=mode==2 ? 0 : 2;write<=1;level<=0;end
       2:begin group_id<=active_hand;item<=0;field<=active_hand ? 2 : 1;level<=3;end
       3:begin level<=2;item<=0;end
       4:begin level<=0;diagnostic<=1;end
      endcase
      2:begin group_id<=item[2:0];field<=field_at(item[2:0],0);item<=0;level<=3;end
      3:if(field==21 || field==27 || field==28)level<=5;else level<=4;
      4:level<=3;
      5:begin value<=field==27 ? 4 : field==28 ? {15'b0,active_hand} : 1;write<=1;level<=3;end
      default:begin end
     endcase
    end
   end
  end
 end
endmodule

module duo04_keys #(parameter CLK_HZ=50000000,DEBOUNCE_MS=20,SHORT_MS=50,LONG_MS=1500,STOP_MS=80)(
 input clk,rst_n,input[2:0]key_n,output reg[11:0]actions);
 reg[2:0]s1,s2,stable,gesture;reg[15:0]db[0:2];reg[31:0]div;
 reg[15:0]held,stop_held,ready_ms;reg armed,stop_sent;integer k;
 wire tick=div==CLK_HZ/1000-1;wire[2:0]down=~stable;
 always @(posedge clk)begin
  if(!rst_n)begin s1<=7;s2<=7;stable<=7;gesture<=0;div<=0;held<=0;stop_held<=0;ready_ms<=0;armed<=0;stop_sent<=0;actions<=0;for(k=0;k<3;k=k+1)db[k]<=0;end
  else begin
   s1<=key_n;s2<=s1;actions<=0;div<=tick ? 0 : div+1'b1;
   if(tick)begin
    for(k=0;k<3;k=k+1)begin
     if(s2[k]==stable[k])db[k]<=0;
     else if(db[k]>=DEBOUNCE_MS-1)begin stable[k]<=s2[k];db[k]<=0;end else db[k]<=db[k]+1'b1;
    end
    if(!armed)begin
     if(s2==7 && stable==7)begin if(ready_ms>=2*DEBOUNCE_MS)armed<=1;else ready_ms<=ready_ms+1'b1;end else ready_ms<=0;
    end else if(down!=0)begin
     gesture<=gesture|down;if(held!=65535)held<=held+1'b1;
     if(down==5 && !stop_sent)begin
      if(stop_held>=STOP_MS-1)begin actions[11]<=1;stop_sent<=1;end else stop_held<=stop_held+1'b1;
     end else stop_held<=0;
    end else begin
     if(held>=SHORT_MS && !stop_sent)case(gesture)
      1:actions[held>=LONG_MS ? 5 : 4]<=1;
      2:if(held<LONG_MS)actions[6]<=1;
      4:actions[held>=LONG_MS ? 8 : 7]<=1;
      3:actions[9]<=1;6:actions[10]<=1;
      default:begin end
     endcase
     gesture<=0;held<=0;stop_sent<=0;stop_held<=0;
    end
   end
  end
 end
endmodule
