`timescale 1ns/1ps
module tb_selection_cursor;
 reg clk=0;always #10.2040816 clk=~clk;
 reg rst_n=0;reg[1087:0]status=0;reg status_update=0;
 wire[7:0]r,g,b,rr,rg,rb;wire hs,vs,de,req,rhs,rvs,rde,rreq;
 duo04_panel dut(clk,rst_n,status,status_update,r,g,b,hs,vs,de,req);
 duo04_panel_reference reference_ui(clk,rst_n,status,status_update,rr,rg,rb,rhs,rvs,rde,rreq);
 wire[9:0]logical_x=dut.x,logical_y=dut.y;
 integer periods=0,cycles=0,pixels=0,hlow=0,vlow=0,compared=0;reg started=0;integer orange=0,grey=0;
 reg expected_de,expected_hs,expected_vs;reg scoreboard_ready=0;
 reg[8:0]legacy[0:8191];integer pg,row,col,id;
 initial begin
  $readmemh("rtl/ui23_text_legacy.hex",legacy);
  #1;
  for(pg=0;pg<4;pg=pg+1)for(row=0;row<30;row=row+1)for(col=0;col<40;col=col+1)
   if(dut.text_rom[pg*2048+row*64+col]!==legacy[pg*1200+row*40+col])$fatal(1,"grid glyph changed");
  for(id=0;id<128;id=id+1)for(col=0;col<20;col=col+1)
   if(dut.text_rom[dut.label_address(id,col)]!==legacy[4800+id*20+col])$fatal(1,"label glyph changed");
  force reference_ui.x=logical_x;force reference_ui.y=logical_y;
  repeat(8)@(negedge clk);rst_n=1;
 end
 always @(negedge clk)if(rst_n)begin
  scoreboard_ready=1;
  if(dut.logical_x!==((dut.beam_x*5)/8)||dut.logical_y!==((dut.beam_y*4)/5))$fatal(1,"UI coordinate mapping");
  expected_de=dut.beam_x3<1024&&dut.beam_y3<600;
  expected_hs=!(dut.beam_x3>=1072&&dut.beam_x3<1168);
  expected_vs=!(dut.beam_y3>=603&&dut.beam_y3<613);
  if(req)begin
   if(started)begin
    if(cycles!=1312*624||pixels!=1024*600||hlow!=96*624||vlow!=10*1312)$fatal(1,"raster counts");
    $display("FRAME_PASS page%0d pixels%0d RGB_comparisons%0d",periods,pixels,compared);
    if(periods==2)begin if(orange!=0 || grey==0)$fatal(1,"offline cursor not grey");end
    else if(orange==0)$fatal(1,"connected selection disappeared with playable=0");
    periods=periods+1;
    if(periods==4)begin $display("TB_PASS selection stays orange with playable0/1, true offline grey;4 native frames:1024x600,1312x624,96/10 sync,full mapping,7360 glyphs and%0d baseline RGB comparisons",compared);$finish;end
   end
   started=1;cycles=0;pixels=0;hlow=0;vlow=0;orange=0;grey=0;
   // Distinct online/calibration/zone/velocity states exercise the
   // per-pixel hand context across x=320 and all dynamic label choices.
   status[255:0]=0;status[511:256]=0;
   status[9:0]=10'h29b;status[21:18]=3;status[127:120]=96;status[159:128]=0;
   status[265:256]=10'h181;status[277:274]=5;status[383:376]=77;status[415:384]=11;
   status[803:802]=0;status[4]=periods[0];status[0]=periods!=2;status[810]=1;status[812:811]=3;status[993:991]=4;status[996:994]=3;status[1000:997]=1;
   status[831:816]=1500;status[879:864]=1023;status[895:880]=23;
   status[1056]=1;status[1087:1076]=2048;status[1075:1064]=1023;
   status_update=1;
  end else status_update=0;
  if(started)begin cycles=cycles+1;pixels=pixels+de;hlow=hlow+!hs;vlow=vlow+!vs;end
  if(started&&de)begin
   if(({r,g,b})!==({rr,rg,rb}))$fatal(1,"UI RGB changed at page%0d x%0d y%0d actual%h reference%h",periods,dut.x2,dut.y2,{r,g,b},{rr,rg,rb});
   compared=compared+1;
   if(dut.x2<320 && {r,g,b}==24'hff7956)orange=orange+1;
   if(dut.x2<320 && {r,g,b}==24'hb5ada0)grey=grey+1;
  end
 end
 always @(posedge clk)begin #1;
  if(rst_n&&scoreboard_ready&&(de!==expected_de||hs!==expected_hs||vs!==expected_vs))$fatal(1,"RGB/sync pipeline alignment");
 end
 initial begin #200000000;$fatal(1,"video timeout");end
endmodule
