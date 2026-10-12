module tb_duo_panel;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg[767:0]status=0;reg status_update=0;wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
 duo_panel dut(.*);integer state,file,pixels;string folder,path;integer hand;
 task publish;begin
 wait(frame_request);@(negedge clk);status_update=1;@(negedge clk);status_update=0;
 end endtask
 initial begin
 if(!$value$plusargs("OUT=%s",folder))folder=".";
 repeat(4)@(negedge clk);rst_n=1;
 for(state=0;state<8;state++)begin
 status=0;status[524]=1;
 if(state!=0)begin
 status[521:520]=3;
 for(hand=0;hand<2;hand++)begin
 status[hand*256+0]=1;status[hand*256+1]=1;status[hand*256+4]=1;status[hand*256+7]=1;
 status[hand*256+8+:2]=3;status[hand*256+18+:4]=hand ? 5 : 1;
 status[hand*256+32+:16]=hand ? 45*16 : -45*16;
 status[hand*256+48+:16]=12*16;status[hand*256+64+:16]=-2*16;
 status[hand*256+176+:16]=123;status[hand*256+160+:16]=456;
 status[640+hand*48+:48]={16'd100,16'd128,16'd100};
 end
 end
 if(state==2 || state==3)begin
 status[32+:16]=-88*16;status[176+:16]=3456;status[192+:32]=37;
 end
 status[523]=state==3 || state==5;
 if(state==4)begin
 status[128+:32]=1;status[22+:4]=1;status[256+128+:32]=1;status[256+22+:4]=5;
 end
 if(state==5)begin status[31]=1;status[256+2]=1;status[256+12+:6]=25;end
 if(state==6)begin status[515:512]=4'b1001;status[256+18+:4]=11;status[18+:4]=3;end
 if(state==7)begin status[4]=0;status[5]=1;status[256+4]=0;status[256+9:256+8]=1;end
 publish();wait(dut.x==0 && dut.y==0);@(negedge clk);#1;
 path=$sformatf("%s/duo-%0d.ppm",folder,state);file=$fopen(path,"wb");if(!file)$fatal(1,"cannot open frame");
 $fwrite(file,"P6\n640 480\n255\n");pixels=0;
 while(pixels<640*480)begin
 if(de)begin $fwrite(file,"%c%c%c",red,green,blue);pixels++;end
 @(negedge clk);#1;end
 $fclose(file);
 end
 $display("TB_PASS 8 dual RTL rasters: disabled, ready, hidden telemetry, diagnostic, both hits, fault/calibration, 5/12, unavailable");$finish;
 end
 initial begin #120000000;$fatal(1,"render timeout");end
endmodule
