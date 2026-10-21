"""Exhaustively compare the actual RTL address expressions with IO22-style math.
Run from WSL/Linux with Icarus, after run_ui23_tests.sh or independently.
"""
from pathlib import Path
import re,subprocess,json,hashlib
R=Path(__file__).resolve().parent;V=R/'validation';V.mkdir(exist_ok=True)
rtl=R/'rtl/duo04_panel.v';s=rtl.read_text(encoding='utf-8')
matches=re.findall(r'^  address=([^;]+);',s,re.M);assert len(matches)==1
src='''`timescale 1ns/1ps
module tb_ui23_address;
reg[1:0]page;reg[4:0]cell_y;reg[5:0]cell_x;wire[12:0]actual;
wire[7:0]red,green,blue;wire hsync,vsync,de,frame_request;
duo04_panel dut(.clk(1'b0),.rst_n(1'b0),.status(1056'b0),.status_update(1'b0),.red(red),.green(green),.blue(blue),.hsync(hsync),.vsync(vsync),.de(de),.frame_request(frame_request));
assign actual=EXPR;
integer p,r,c,id,checks;
initial begin
checks=0;
for(p=0;p<4;p=p+1)for(r=0;r<32;r=r+1)for(c=0;c<64;c=c+1)begin
page=p;cell_y=r;cell_x=c;#1;
if(actual!=p*1200+r*40+c)$fatal(1,"grid address %0d/%0d/%0d",p,r,c);checks++;
end
for(id=0;id<128;id=id+1)for(c=0;c<64;c=c+1)begin
if(dut.label_address(id[6:0],c[5:0])!=(c<20 ? 4800+id*20+c : 0))$fatal(1,"label address %0d/%0d",id,c);checks++;
end
$display("TB_PASS %0d grid/label addresses equal constant multiply reference",checks);$finish;
end endmodule
'''.replace('EXPR',matches[0])
(V/'ui23_address_equivalence.sv').write_text(src,encoding='ascii')
subprocess.run(['iverilog','-g2012','-s','tb_ui23_address','-o',str(V/'ui23_address.vvp'),str(V/'ui23_address_equivalence.sv'),'rtl/duo04_panel.v','rtl/duo_fan.v'],cwd=R,check=True)
run=subprocess.run(['vvp',str(V/'ui23_address.vvp')],cwd=R,capture_output=True,text=True,check=True)
assert 'TB_PASS 16384' in run.stdout
(V/'ui23_address.log').write_text(run.stdout,encoding='utf-8')
(V/'ui23_address.json').write_text(json.dumps({'status':'PASS','checks':16384,'rtl_sha256':hashlib.sha256(rtl.read_bytes()).hexdigest(),'actual_grid_expression':matches[0],'golden_reference':'p*1200+r*40+c; 4800+id*20+col with col<20 guard'},indent=2),encoding='utf-8')
print(run.stdout)
