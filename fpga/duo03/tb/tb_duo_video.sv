`timescale 1ns/1ps
// Actual 50MHz board video adapter, clock shim supplies its 25MHz pixel clock.
// Only vendor PLL/TMDS are excluded; both renderers and full1024 CDC are real.
module tb_duo_video;
 reg clk50=0;always #10 clk50=~clk50;reg rst_n=0;
 reg[1023:0]performance_status=0;wire tmds_clk_p,tmds_clk_n;wire[2:0]tmds_d_p,tmds_d_n;
 video_duo03_hdmi dut(.*);integer file,pixels,state,h;string folder,path;
 task capture(input integer id);
 begin
  @(posedge dut.pixel_status_valid);@(posedge dut.pixel_clk);@(negedge dut.pixel_clk);#1;
  if(dut.panel.performance.y<480)$fatal(1,"snapshot during active scan");
  if(dut.pixel_status!==performance_status || dut.panel.performance.ui!==performance_status[799:0] || dut.panel.menu.ui!==performance_status[927:800])$fatal(1,"full frame data packing");
  if(dut.panel.menu_visible!==performance_status[860])$fatal(1,"visibility snapshot skew");
  wait(dut.panel.performance.x==0 && dut.panel.performance.y==0);@(negedge dut.pixel_clk);#1;
  path=$sformatf("%s/page-%0d.ppm",folder,id);file=$fopen(path,"wb");if(!file)$fatal(1,"page output path");
  $fwrite(file,"P6\n640 480\n255\n");pixels=0;
  while(pixels<640*480)begin
   if(dut.de)begin $fwrite(file,"%c%c%c",dut.red,dut.green,dut.blue);pixels++;end
   @(negedge dut.pixel_clk);#1;
  end
  $fclose(file);
 end endtask
 always @(negedge dut.pixel_clk)if(dut.pixel_reset_n)begin
  if({dut.panel.ph,dut.panel.pv,dut.panel.pd,dut.panel.pframe}!=={dut.panel.mh,dut.panel.mv,dut.panel.md,dut.panel.mframe})$fatal(1,"menu/performance raster phase mismatch");
 end
 initial begin
  if(!$value$plusargs("OUT=%s",folder))folder=".";
  repeat(6)@(negedge clk50);rst_n=1;
  for(state=0;state<8;state++)begin
   @(negedge clk50);performance_status=0;
   performance_status[521:520]=3;performance_status[524]=1;performance_status[787:780]=144;
   performance_status[779:778]=3;performance_status[777:776]=3;
   for(h=0;h<2;h++)begin
    performance_status[h*256]=1;performance_status[h*256+1]=1;performance_status[h*256+3]=1;
    performance_status[h*256+4]=1;performance_status[h*256+7]=1;performance_status[h*256+8+:2]=3;
    performance_status[h*256+18+:4]=h ? 5 : 1;
   end
   // Menu targets and actual state, coherent but intentionally different during drain.
   performance_status[860]=state>=2 && state<=4;
   performance_status[803:800]=5;performance_status[804]=state==4;performance_status[805]=state==4;
   performance_status[806]=1;performance_status[815:812]=5;performance_status[821:820]=3;
   performance_status[829:822]=255;performance_status[843:830]=16368;
   performance_status[851:844]=128;performance_status[859:852]=96;
   performance_status[865:864]=state==2 ? 1 : 3;
   performance_status[873:866]=state==2 ? 64 : 255;
   performance_status[887:874]=state==2 ? 4800 : 16368;
   performance_status[895:888]=state==2 ? 96 : 128;performance_status[903:896]=96;
   performance_status[904]=state==2;
   if(state==1 || state==7)performance_status[523]=1;
   if(state==4)begin performance_status[803:800]=6;performance_status[821:820]=2;performance_status[865:864]=2;performance_status[851:844]=0;end
   if(state==6 || state==7)begin performance_status[32+:16]=-88*16;performance_status[192+:32]=37;end
   capture(state);
  end
  $display("TB_PASS DUO03 board video adapter: 50/25MHz, full1024 CDC/atomic visibility, equal rasters, main/diagnostic/menu targets and live effect transition, hidden telemetry; eight RTL frames");$finish;
 end
 initial begin #300000000;$fatal(1,"video watchdog");end
endmodule
