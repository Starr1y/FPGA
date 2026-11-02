`timescale 1ns/1ps
module tb_ui23_panel;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,status_update=0;reg[1055:0]status=0;
 wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 duo04_panel dut(.*);
 integer file,pixels,scene,warm_pixels,fan_pixels;
 reg[23:0]pixel;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(scene=0;scene<16;scene=scene+1)begin
   @(negedge clk);status=0;
   status[810]=1;status[812:811]=3;status[928:920]=179;
   status[901:896]={3'd1,3'd0};status[3:0]=3;status[9:8]=3;status[7]=1;status[4]=1;
   status[259:256]=3;status[265:264]=3;status[263]=1;status[260]=1;
   status[21:18]=3;status[277:274]=4;status[127:120]=78;status[383:376]=65;
   case(scene)
    1:begin status[803:802]=1;status[993:991]=1;status[1000:997]=0;end
    2:begin status[803:802]=2;status[847:840]=4;status[852:849]=2;status[879:864]=4;status[895:880]=1;end
    3:begin status[803:802]=3;status[812]=0;status[511:256]=0;end
    4:begin status[803:802]=1;status[993:991]=4;status[996:994]=0;status[1000:997]=3;status[808:804]=11;status[831:816]=1500;end
    5:begin status[907:904]=4'b1010;status[21:18]=10;status[277:274]=8;end
    6:begin status[907:904]=4'b0101;status[21:18]=2;status[277:274]=3;end
    7:begin status[803:802]=2;status[1003:1002]=1;status[1008:1005]=2;status[852:849]=2;end
    8:begin status[803:802]=2;status[1003:1002]=2;status[1004]=1;status[1008:1005]=4;end
    9:begin status[803:802]=1;status[993:991]=5;status[996:994]=5;status[1000:997]=3;status[808:804]=28;end
    10:begin status[810]=0;status[812]=0;status[511:256]=0;end
    11:begin status[803:802]=2;status[989]=1;status[847:840]=16;status[879:864]=16;end
    12:begin status[159:128]=1;status[25:22]=4;end
    14:begin status[803:802]=1;status[993:991]=4;status[996:994]=3;status[1000:997]=1;status[808:804]=29;status[831:816]=1;end
    15:begin status[1037:1036]=3;status[1041:1038]=4'b0110;end
    13:begin status[801:800]=1;status[812:811]=0;status[159:128]=2;status[25:22]=1;status[127:120]=0;status[383:376]=0;end
   endcase
   status_update=1;@(negedge clk);status_update=0;
   wait(dut.x==0 && dut.y==0);repeat(4)@(negedge clk);
   file=$fopen($sformatf("preview/ui23-%0d.ppm",scene),"wb");
   $fwrite(file,"P6\n640 480\n255\n");if(!file)$fatal(1,"image output missing");pixels=0;warm_pixels=0;fan_pixels=0;
   while(pixels<640*480)begin
    @(negedge clk);
    if(de)begin
     if((^dut.glyph)===1'bx || (^dut.bits)===1'bx || (^dut.fan_zones2)===1'bx || ((^{red,green,blue})===1'bx))$fatal(1,"unknown visible output scene %0d",scene);
     if(dut.glyph>=256)$fatal(1,"glyph truncation scene %0d",scene);
     pixel={red,green,blue};
     if(pixel==24'hfffdf7)warm_pixels++;
     if(dut.fan_zones2!=0)fan_pixels++;
     $fwrite(file,"%c%c%c",red,green,blue);pixels++;
    end
   end
   $fclose(file);
   if(warm_pixels<30000)$fatal(1,"missing warm cards scene %0d",scene);
   if((scene==0 || scene==2 || scene>=5 && scene<=8 || scene==10 || scene==11) && fan_pixels<2000)$fatal(1,"missing fan scene %0d",scene);
   $display("SCENE_PASS %0d raster=%0d card=%0d fan=%0d",scene,pixels,warm_pixels,fan_pixels);
  end
  $display("TB_PASS UI23 fourteen full raster scenes: pages, edit/confirm, 5/7/12 notes, lesson right/wrong/completed, strike, offline/stop and host input");$finish;
 end
endmodule
