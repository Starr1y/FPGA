`timescale 1ns/1ps
module tb_calibration_render;
 reg clk=0;always #20 clk=!clk;
 reg rst_n=0,status_update=0;reg [1023:0] performance_status=0;
 wire [7:0] red,green,blue;wire hsync,vsync,de,frame_request;
 video_instrument_panel dut(.clk(clk),.rst_n(rst_n),.levels(40'd0),.mix_sample(8'd0),.sample_update(1'b0),
 .performance_status(performance_status),.status_update(status_update),.red(red),.green(green),.blue(blue),.hsync(hsync),.vsync(vsync),.de(de),.frame_request(frame_request));
 integer file,state,pixels;string folder,path;
 task publish;begin
 status_update=1;@(negedge clk);status_update=0;repeat(600)@(negedge clk);
 end endtask
 initial begin
 if(!$value$plusargs("OUT=%s",folder))$fatal(1,"OUT missing");
 repeat(3)@(negedge clk);rst_n=1;
 for(state=0;state<9;state++)begin
 performance_status=0;performance_status[242:240]=3;performance_status[103:96]=128;
 performance_status[965]=1;performance_status[906]=1;performance_status[968]=1;
 performance_status[969]=state!=0;
 performance_status[249:247]=state==0 ? 6 : state==1 ? 2 : 3;
 if(state>=2)begin
 performance_status[3:0]=7;performance_status[5:4]=3;performance_status[6]=1;performance_status[7]=1;
 performance_status[14]=1;performance_status[9]=1;performance_status[254:250]=31;
 performance_status[929:914]=1234;performance_status[945:930]=238;
 performance_status[127:112]=200;performance_status[143:128]=500;performance_status[159:144]=200;
 performance_status[31:16]=-20*16;performance_status[47:32]=12*16;performance_status[63:48]=5*16;
 performance_status[79:64]=-12;performance_status[242:240]=2;
 performance_status[1000:999]=2;performance_status[1002:1001]=3;
 end
 if(state==3)begin
 performance_status[15]=1;performance_status[223:192]=7;performance_status[226:224]=2;
 performance_status[235]=1;performance_status[111:104]=96;
 end
 if(state==4)begin
 performance_status[249:247]=5;performance_status[3:0]=0;performance_status[6]=0;
 performance_status[973:970]=3;performance_status[989:974]=16'hffff;performance_status[991:990]=1;
 performance_status[929:914]=24;performance_status[945:930]=0;performance_status[191:160]=6;
 performance_status[961:946]=2;
 end
 if(state>=5)begin
 performance_status[7]=0;performance_status[9]=0;performance_status[15]=0;performance_status[233+:7]=0;
 performance_status[3:0]=state==5 ? 3 : state==6 ? 10 : state==7 ? 9 : 1;
 performance_status[5:4]=state==5 || state==7 ? 0 : 3;
 performance_status[8]=state!=7;performance_status[232:227]=state==8 ? 25 : 0;
 end
 publish();
 wait(dut.x==0 && dut.y==0);@(negedge clk);#1;
 path=$sformatf("%s/ui-state-%0d.ppm",folder,state);file=$fopen(path,"wb");if(!file)$fatal(1,"open failed");
 $fwrite(file,"P6\n640 480\n255\n");pixels=0;
 while(pixels<640*480)begin
 if(de)begin $fwrite(file,"%c%c%c",red,green,blue);pixels++;end
 @(negedge clk);#1;
 end
 $fclose(file);
 end
 $display("TB_PASS rendered disabled/configuring/ready/hit/fault full native rasters");$finish;
 end
 initial begin #220000000;$fatal(1,"render watchdog");end
endmodule
