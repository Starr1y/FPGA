`timescale 1ns/1ps
module tb_duo04_panel;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,status_update=0;reg[1087:0]status=0;
 wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 duo04_panel dut(.*);
 integer file,rows,pixels,page;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(page=0;page<4;page++)begin
   @(negedge clk);status=0;status[803:802]=page;status[810]=1;
   status[831:816]=1500;status[808:804]=11;
   status[863:856]=60;status[852:849]=0;status[847:840]=3;
   status[895:880]=2;status[879:864]=3;
   status[901:896]={3'd3,3'd0};status[812:811]=3;
   status[21:18]=2;status[4]=1;status[277:274]=4;status[260]=1;
   status_update=1;@(negedge clk);status_update=0;
   // Start at the first output pixel of a complete frame, independent of
   // pipeline depth; the legacy bench's fixed delay cut into the first row.
   wait(dut.raster_x==1311 && dut.raster_y==623);@(negedge clk);
   while(!de)@(negedge clk);
   case(page)0:file=$fopen("panel0.ppm","w");1:file=$fopen("panel1.ppm","w");2:file=$fopen("panel2.ppm","w");default:file=$fopen("panel3.ppm","w");endcase
   $fwrite(file,"P3\n1024 600\n255\n");pixels=0;
   while(pixels<1024*600)begin
    if(de)begin
     if($isunknown({red,green,blue}))$fatal(1,"unknown RGB");
     $fwrite(file,"%d %d %d\n",red,green,blue);pixels++;
    end
    @(negedge clk);
   end
   $fclose(file);
  end
  $display("TB_PASS four pages rendered, no unknown pixels");$finish;
 end
endmodule
