`timescale 1ns/1ps
module tb_ui_render;
 reg clk=0;always #20 clk=!clk;
 reg rst_n=0,status_update=0;reg [1023:0] performance_status=0;
 wire [7:0] red,green,blue;wire hsync,vsync,de,frame_request;
 video_instrument_panel dut(.clk(clk),.rst_n(rst_n),.levels(40'd0),.mix_sample(8'd0),.sample_update(1'b0),
 .performance_status(performance_status),.status_update(status_update),.red(red),.green(green),.blue(blue),.hsync(hsync),.vsync(vsync),.de(de),.frame_request(frame_request));
 integer file,state,pixels,page;string folder,path;
 task publish;begin
 status_update=1;@(negedge clk);status_update=0;repeat(600)@(negedge clk);
 end endtask
 initial begin
 if(!$value$plusargs("OUT=%s",folder))$fatal(1,"OUT missing");
 repeat(3)@(negedge clk);rst_n=1;
 for(page=0;page<2;page++)begin
 for(state=0;state<17;state++)begin
 performance_status=0;performance_status[1021]=1;performance_status[1020:1017]=7;performance_status[1008:1005]=3;performance_status[242:240]=3;performance_status[103:96]=128;
 performance_status[965]=1;performance_status[906]=1;performance_status[968]=1;
 performance_status[969]=state!=0;
 performance_status[249:247]=state==0 ? 6 : state==1 ? 2 : 3;
 if(state>=2)begin
 performance_status[3:0]=7;performance_status[5:4]=3;performance_status[6]=1;performance_status[7]=1;
 performance_status[14]=1;performance_status[9]=1;performance_status[254:250]=31;
 performance_status[929:914]=1234;performance_status[945:930]=238;
 performance_status[127:112]=200;performance_status[143:128]=500;performance_status[159:144]=200;
 performance_status[31:16]=-20*16;performance_status[47:32]=12*16;performance_status[63:48]=5*16;
 performance_status[79:64]=-12;performance_status[242:240]=2;performance_status[1008:1005]=2;
 performance_status[1000:999]=2;performance_status[1002:1001]=3;
 end
 performance_status[309:308]=state>=2 ? state%4 : 0;
 if(state==3)begin
 performance_status[15]=1;performance_status[223:192]=7;performance_status[226:224]=2;
 performance_status[235]=1;performance_status[322]=1;performance_status[1012:1009]=2;performance_status[111:104]=96;
 end
 if(state==4)begin
 performance_status[249:247]=5;performance_status[3:0]=0;performance_status[6]=0;
 performance_status[973:970]=3;performance_status[989:974]=16'hffff;performance_status[991:990]=1;
 performance_status[929:914]=24;performance_status[945:930]=0;performance_status[191:160]=6;
 performance_status[961:946]=2;
 end
 if(state>=5 && state<9)begin
 performance_status[7]=0;performance_status[9]=0;performance_status[15]=0;performance_status[233+:7]=0;
 performance_status[3:0]=state==5 ? 3 : state==6 ? 10 : state==7 ? 9 : 1;
 performance_status[5:4]=state==5 || state==7 ? 0 : 3;
 performance_status[8]=state!=7;performance_status[232:227]=state==8 ? 25 : 0;
 end
performance_status[1003]=page;
if(state==10)performance_status[1004]=1;
if(state==9)begin performance_status[31:16]=35*16;performance_status[47:32]=-8*16;performance_status[63:48]=88*16;performance_status[929:914]=8765;performance_status[945:930]=654;performance_status[191:160]=23;performance_status[961:946]=3;performance_status[127:112]=120;end
if(state>=11)begin
 performance_status[1014:1013]=state<14 ? 1 : 2;
 performance_status[1020:1017]=state<14 ? 5 : 12;
 performance_status[1008:1005]=state<14 ? 3 : 11;
 if(state==12 || state==15)begin performance_status[15]=1;performance_status[223:192]=8;performance_status[1012:1009]=state<14 ? 3 : 11;performance_status[1016:1015]=state<14 ? 1 : 2;performance_status[state<14 ? 323 : 331]=1;end
 if(state==13 || state==16)begin performance_status[3:0]=5;performance_status[12]=1;end
 end
publish();
 wait(dut.x==0 && dut.y==0);@(negedge clk);#1;
 path=$sformatf("%s/ui-page-%0d-state-%0d.ppm",folder,page,state);file=$fopen(path,"wb");if(!file)$fatal(1,"open failed");
 $fwrite(file,"P6\n640 480\n255\n");pixels=0;
 while(pixels<640*480)begin
 if(de)begin $fwrite(file,"%c%c%c",red,green,blue);pixels++;end
 @(negedge clk);#1;
 end
 $fclose(file);
 end
 end
$display("TB_PASS rendered both pages with primary status, calibration, faults and hits");$finish;
 end
 initial begin #900000000;$fatal(1,"render watchdog");end
endmodule
