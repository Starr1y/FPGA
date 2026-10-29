from pathlib import Path
import math, subprocess
r=Path('C:/Users/LPC/Desktop/fpga_gowin/bno085_pc_tool/fpga/duo04-stable26')
out=Path('D:/codex/tasks/2026-10-25/tanglab-stable26/pose-axis-check')
out.mkdir(exist_ok=True)
def mul(a,b):
 x,y,z,w=a;X,Y,Z,W=b
 return (w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z)
def axis(a,d):
 q=[0.,0.,0.,math.cos(math.radians(d)/2)];q[a]=math.sin(math.radians(d)/2);return q
def args(q):return ','.join(str(round(v*16384)) for v in q)
cases=[]
for yaw in (0,45,135,180,-135):
 for tilt in (0,30,-30):
  origin=mul(axis(2,yaw),axis(0,tilt))
  cases.append(f'cal({args(origin)});')
  for pitch in (-60,-30,0,30,60):
   q=mul(origin,axis(1,pitch))
   cases.append(f'check({args(q)},0,{pitch*16},0);');cases.append(f'check({args(tuple(-v for v in q))},0,{pitch*16},0);')
  for turn in (-179,-90,-45,-20,0,20,45,90,179):
   q=mul(origin,axis(2,turn));cases.append(f'check({args(q)},{turn*16},0,0);')
  for turn in (-45,0,45):
   for pitch in (-45,45):
    q=mul(origin,mul(axis(2,turn),axis(1,pitch)));cases.append(f'check({args(q)},{turn*16},{pitch*16},0);')
text='''`timescale 1ns/1ps
module tb_pose_axes;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,calibrate=0,quat_valid=0;reg signed[15:0]qx=0,qy=0,qz=0,qw=16384;
wire calibrated,calibrating,pose_valid;wire signed[15:0]yaw,pitch,roll;
integer failures=0,checks=0;
quaternion_pose #(.CLK_HZ(1000),.CAL_TIMEOUT_TICKS(200000)) dut(.clk(clk),.rst_n(rst_n),.sensor_restarted(1'b0),.online(1'b1),.calibrate(calibrate),.quat_valid(quat_valid),.qx(qx),.qy(qy),.qz(qz),.qw(qw),.accuracy(2'd3),.gx(16'd0),.gy(16'd0),.gz(16'd0),.quat_sequence(8'd0),.quat_timestamp_ticks(32'd0),.quat_timestamp_valid(1'b1),.calibrated(calibrated),.calibrating(calibrating),.pose_valid(pose_valid),.yaw(yaw),.pitch(pitch),.roll(roll));
task sample(input integer x,y,z,w);begin
 @(negedge clk);qx=x;qy=y;qz=z;qw=w;quat_valid=1;
 @(negedge clk);quat_valid=0;repeat(400)@(negedge clk);
end endtask
task cal(input integer x,y,z,w);begin
 @(negedge clk);calibrate=1;@(negedge clk);calibrate=0;
 repeat(52)sample(x,y,z,w);
 if(!calibrated)$fatal(1,"calibration failed");
end endtask
task check(input integer x,y,z,w,ey,ep,er);begin
 sample(x,y,z,w);checks=checks+1;
 if(yaw<ey-12 || yaw>ey+12 || pitch<ep-12 || pitch>ep+12 || roll<er-12 || roll>er+12)begin
 failures=failures+1;$display("FAIL q=%d,%d,%d,%d yaw=%d pitch=%d roll=%d expected=%d,%d,%d",x,y,z,w,yaw,pitch,roll,ey,ep,er);
 end
end endtask
initial begin repeat(5)@(negedge clk);rst_n=1;
'''+ '\n'.join(cases)+'''
 $display("CHECKS %d FAILURES %d",checks,failures);
 if(failures)$fatal(1,"pose axes failed");$display("TB_PASS");$finish;
end
initial begin #100000000;$fatal(1,"watchdog");end
endmodule
'''
(out/'tb_pose_axes.sv').write_text(text,encoding='utf8')
for name,cmd in [('compile',['xvlog.bat',str(r/'rtl/pose_math.v'),str(r/'rtl/quaternion_pose.v'),'--sv',str(out/'tb_pose_axes.sv')]),('elaborate',['xelab.bat','tb_pose_axes','-s','axes_sim','-timescale','1ns/1ps']),('run',['xsim.bat','axes_sim','-runall'])]:
 p=subprocess.run(cmd,cwd=out,capture_output=True,text=True,errors='replace',timeout=120)
 (out/(name+'.log')).write_text(p.stdout+p.stderr,encoding='utf8')
 print(name,p.returncode,(p.stdout+p.stderr)[-5000:],flush=True)
 if p.returncode:raise SystemExit(p.returncode)

