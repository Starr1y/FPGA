module tb_duo_keys;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg k0=1,k1=1,k2=1;wire focus,diagnostic,muted,chord_mode,combo_active;
 wire[1:0]enabled,calibrate,force_reset,express;wire[3:0]profiles,presets;
 wire[1:0]effect_mode;wire[7:0]effect_wet;
 duo_keys #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.SHORT_MS(5),.LONG_MS(20),.COMBO_MS(30),.EXPRESS_MS(10)) dut(
  .clk(clk),.rst_n(rst_n),.key0_n(k0),.key1_n(k1),.key2_n(k2),.*);
 integer origins[0:1],resets[0:1];integer i;
 always @(posedge clk)if(rst_n)for(i=0;i<2;i++)begin
  if(calibrate[i])origins[i]++;if(force_reset[i])resets[i]++;
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task single(input integer key,input integer ms);
 begin case(key)0:k0=0;1:k1=0;2:k2=0;endcase cycles(ms);
 k0=1;k1=1;k2=1;cycles(8);end endtask
 task pair(input integer mask,input integer ms,input bit skew);
 begin {k2,k1,k0}=~mask[2:0];cycles(ms);
 if(skew)begin if(mask[2])k2=1;else k1=1;cycles(4);end
 k0=1;k1=1;k2=1;cycles(8);end endtask
 initial begin
 origins[0]=0;origins[1]=0;resets[0]=0;resets[1]=0;cycles(4);rst_n=1;cycles(4);
 if(enabled!=0 || !muted)$fatal(1,"unsafe defaults");
 // Contact bounce shorter than debounce is ignored.
 k0=0;cycles(1);k0=1;cycles(4);if(origins[0])$fatal(1,"bounce origin");
 pair(6,16,1);if(!diagnostic || enabled!=0 || focus || presets!=0)$fatal(1,"short/skewed combo");
 pair(6,40,1);if(enabled!=1 || !diagnostic)$fatal(1,"long combo must enable focused hand only");
 single(0,12);if(origins[0]!=1 || origins[1]!=0)$fatal(1,"origin ownership");
 single(0,28);if(profiles!=1 || origins[0]!=1)$fatal(1,"layout hold fired origin");
 single(1,9);if(presets!=1)$fatal(1,"short preset");
 k1=0;cycles(18);if(express!=1)$fatal(1,"physical KEY1 express");k1=1;cycles(8);
 if(express!=0 || presets!=1)$fatal(1,"express release cycled preset");
 single(2,12);if(!focus || resets[0])$fatal(1,"focus short");
 pair(6,40,0);if(enabled!=3)$fatal(1,"second enable changed first");
 single(0,12);if(origins[1]!=1)$fatal(1,"second origin");
 single(2,28);if(resets[1]!=1 || resets[0]!=0 || !focus)$fatal(1,"reset long switched focus");
 pair(5,40,1);if(muted || origins[1]!=1 || resets[1]!=1)$fatal(1,"mute combo singles leaked");
 pair(3,40,1);if(!chord_mode || presets!=1 || profiles!=1)$fatal(1,"mode combo singles leaked");
 pair(6,40,0);if(enabled!=1)$fatal(1,"right disable killed left");
 // Interrupted combo cannot add separated fragments to qualify as a long hold.
 k1=0;k2=0;cycles(18);k2=1;cycles(6);k2=0;cycles(18);k1=1;k2=1;cycles(8);
 if(enabled!=1)$fatal(1,"interrupted hold enabled hand");
 pair(7,40,1);if(effect_mode!=1 || effect_wet!=128 || enabled!=1 || !chord_mode || muted)$fatal(1,"three-key effect changed unrelated controls");
 pair(7,16,1);if(effect_mode!=1 || effect_wet!=160)$fatal(1,"three-key wet short");
 k1=0;k2=0;cycles(10);k0=0;cycles(40);k2=1;cycles(4);k1=1;k0=1;cycles(8);
 if(effect_mode!=2 || effect_wet!=160 || enabled!=1)$fatal(1,"late third key must start fresh triple hold");
 repeat(3)pair(7,16,0);if(effect_wet!=32)$fatal(1,"wet setting wrap");
 $display("TB_PASS dual controls, bounce/release skew, focused origins/reset, expression, triple mode/wet and late-third upgrade");$finish;
 end
endmodule
