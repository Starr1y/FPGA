`timescale 1ns/1ps
module tb_score27_panel;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,status_update=0;reg[1087:0]status=0;
 wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 duo04_panel dut(.*);
 integer file,pixels,scene,warm_pixels,fan_pixels;
 reg[23:0]pixel;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(scene=0;scene<2;scene=scene+1)begin
   @(negedge clk);status=0;
   status[810]=1;status[812:811]=3;status[928:920]=179;
   status[901:896]={3'd1,3'd0};status[3:0]=3;status[9:8]=3;status[7]=1;status[4]=1;
   status[259:256]=3;status[265:264]=3;status[263]=1;status[260]=1;
   status[21:18]=3;status[277:274]=4;status[127:120]=78;status[383:376]=65;
   status[803:802]=2;status[801:800]=2;status[833:832]=3;status[1087:1076]=2048;status[1075:1064]=scene==0 ? 1023 : 2048;status[1056]=1;status[1057]=1;
   status[852:849]=2;status[847:840]=255;status[879:864]=1023;
   if(scene==1)status[989]=1;
   status_update=1;@(negedge clk);status_update=0;
   wait(dut.x==0 && dut.y==0);repeat(4)@(negedge clk);
   file=$fopen($sformatf("preview/score27-%0d.ppm",scene),"wb");
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
  $display("TB_PASS GEST27 uploaded 2048 step course / current target / completed raster");$finish;
 end
endmodule
