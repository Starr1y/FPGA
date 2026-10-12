`timescale 1ns/1ps
module tb_menu_panel;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg[63:0]status=0;reg status_update=0;wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 menu_panel dut(.*);
 integer state,file,pixels;string folder,path;
 function[15:0]decimal_bcd(input integer n);
  begin decimal_bcd=((n/1000)%10)<<12 | ((n/100)%10)<<8 | ((n/10)%10)<<4 | n%10;end
 endfunction
 task publish;
 begin wait(frame_request);@(negedge clk);status_update=1;@(negedge clk);status_update=0;
  wait(dut.format_state==0);@(negedge clk);
  // Integer reference is deliberately only in the bench, not the pixel datapath.
  if(dut.bcd[0]!==decimal_bcd(status[43:30]/48) || dut.bcd[1]!==decimal_bcd((status[29:22]*100)/256) ||
    dut.bcd[2]!==decimal_bcd((status[51:44]*100)/256) || dut.bcd[3]!==decimal_bcd(status[59:52]))$fatal(1,"menu units/decimal formatting");
 end endtask
 initial begin
  if(!$value$plusargs("OUT=%s",folder))folder=".";
  repeat(4)@(negedge clk);rst_n=1;
  for(state=0;state<15;state++)begin
   status=0;status[60]=state!=0;status[6]=1;status[15:12]=5;status[29:22]=128;status[43:30]=4800;status[51:44]=96;status[59:52]=96;
   if(state>=2 && state<=12)begin status[3:0]=state-2;status[4]=1;end
   if(state==3)begin status[5]=1;status[11:8]=4'b1101;end
   if(state==4)status[15:12]=4'b0110;
   if(state==5)status[21:20]=3;
   if(state==6)status[29:22]=255;
   if(state==7)status[43:30]=16368;
   if(state==8)begin status[21:20]=2;status[51:44]=0;end
   if(state==9)status[59:52]=255;
   if(state==10)status[7]=1;
   if(state==11)status[6]=0;
   if(state==12)status[19:16]=2;
   if(state==13)begin status[3:0]=6;status[21:20]=3;status[51:44]=128;status[43:30]=48;status[29:22]=0;end
   if(state==14)begin status[3:0]=6;status[21:20]=1;status[51:44]=192;end
   publish();wait(dut.x==0 && dut.y==0);@(negedge clk);#1;
   path=$sformatf("%s/menu-%0d.ppm",folder,state);file=$fopen(path,"wb");if(!file)$fatal(1,"menu output path");
   $fwrite(file,"P6\n640 480\n255\n");pixels=0;
   while(pixels<640*480)begin
    if(de)begin $fwrite(file,"%c%c%c",red,green,blue);pixels++;end
    @(negedge clk);#1;
   end
   $fclose(file);
  end
  $display("TB_PASS 15 menu RTL rasters: hidden/open, every item edit, both hands, units/decimal bounds, chorus fixed feedback, tail/layout/mute/mode settings");$finish;
 end
 initial begin #150000000;$fatal(1,"menu raster watchdog");end
endmodule
