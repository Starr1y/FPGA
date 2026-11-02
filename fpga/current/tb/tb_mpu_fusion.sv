`timescale 1ns/1ps
module tb_mpu_fusion;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,clear=0,sv=0;reg[31:0]stamp=0;
 reg signed[15:0]ax=0,ay=0,az=8192,gx=0,gy=0,gz=0;
 wire ready,valid;wire signed[15:0]qx,qy,qz,qw;wire[31:0]errors;
 integer f,out,k,code,idx=0;real ex,ey,ez,ew;
 mpu6050_fusion d(.clk(clk),.rst_n(rst_n),.clear(clear),.online(1'b1),.sample_valid(sv),.sample_tick(stamp),.ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.ready(ready),.valid(valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.errors(errors));
 initial begin
  f=$fopen("fusion_vectors.txt","r");out=$fopen("fusion_output.txt","w");
  repeat(5)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   code=$fscanf(f,"%d %d %d %d %d %d %d %d %f %f %f %f\n",k,stamp,ax,ay,az,gx,gy,gz,ex,ey,ez,ew);
   if(code==12)begin
    if(k)begin clear=1;repeat(4)@(negedge clk);clear=0;end
    sv=1;@(negedge clk);sv=0;
    repeat(1000)@(negedge clk);
    $fwrite(out,"%d %d %d %d %d %d %d %d\n",idx,ready,qx,qy,qz,qw,errors,d.state);
    idx=idx+1;
   end
  end
  $fclose(f);$fclose(out);$display("TB_PASS fusion vectors processed%0d",idx);$finish;
 end
 initial begin #200000000;$fatal(1,"fusion timeout");end
endmodule
