"""Generate the board constraints and HDMI adapter from verified FAN04 primitives."""
from pathlib import Path
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo01';F=R/'fpga/i2cfan04'
def main():
 s=(F/'rtl/video_hdmi.v').read_text();s=s.replace('module video_hdmi(', 'module video_duo_hdmi(').replace('    input [79:0] samples, input sample_valid,\n','').replace('[1023:0]','[767:0]').replace('.WIDTH(1024)','.WIDTH(768)')
 a=s.index('    // Audio samples');b=s.index('    wire clocks_ready',a)
 s=s[:a]+s[b:];a=s.index('    always @(posedge pixel_clk) begin',s.index('wire pixel_reset_n'));b=s.index('    wire [7:0] red',a);s=s[:a]+s[b:]
 a=s.index('    video_instrument_panel');b=s.index('    // Separate procedural',a)
 s=s[:a]+'''    duo_panel panel(.clk(pixel_clk),.rst_n(pixel_reset_n),.status(pixel_status),.status_update(pixel_status_valid),
      .frame_request(frame_request),.red(red),.green(green),.blue(blue),.hsync(hsync),.vsync(vsync),.de(de));
'''+s[b:]
 (W/'rtl/video_duo_hdmi.v').write_text(s)
 pins={'clk':('V22','LVCMOS33','NONE',3.3),'reset_key':('F4','LVCMOS15','DOWN',1.5),
       'key0_n':('AA13','LVCMOS33','UP',3.3),'key1_n':('Y12','LVCMOS33','UP',3.3),'key2_n':('AB13','LVCMOS33','UP',3.3)}
 for name,balls in [('imu_scl',['E19','D19']),('imu_sda',['C18','C19']),('imu_int_n',['E16','E17']),('imu_rst_n',['D20','F16'])]:
  for i,ball in enumerate(balls):pins[f'{name}[{i}]']=(ball,'LVCMOS33','NONE',3.3)
 for name,ball in [('hp_bck','Y17'),('hp_ws','AB17'),('hp_din','AA16'),('pa_en','AB16')]:pins[name]=(ball,'LVCMOS33','NONE',3.3)
 c='// NEO Rev1.4 PDF pages7/10/19. No SPI outputs, no GPIO power-good bypass.\n'
 for name,(ball,typ,pull,vcc) in pins.items():c+=f'IO_LOC "{name}" {ball};\nIO_PORT "{name}" IO_TYPE={typ} BANK_VCCIO={vcc} PULL_MODE={pull};\n'
 old=(F/'tanglab_i2c_fan04.cst').read_text();c+=old[old.index('IO_LOC "tmds_d_p_0[0]"'):]
 (W/'tanglab_duo01.cst').write_text(c)
 s=(F/'tanglab_i2c_fan04.sdc').read_text().replace('core/display/','display/')
 (W/'tanglab_duo01.sdc').write_text(s)
 head='<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE gowin-fpga-project>\n<Project><Template>FPGA</Template><Version>5</Version><Device name="GW5AST-138C" pn="GW5AST-LV138PG484AC1/I0">gw5ast138c-007</Device><FileList>\n'
 for p in sorted((W/'rtl').glob('*.v')):head+=f'<File path="rtl/{p.name}" type="file.verilog" enable="1"/>\n'
 head+='<File path="tanglab_duo01.cst" type="file.cst" enable="1"/><File path="tanglab_duo01.sdc" type="file.sdc" enable="1"/>\n</FileList></Project>\n'
 (W/'tanglab_duo01.gprj').write_text(head)
 (W/'build.tcl').write_text('open_project tanglab_duo01.gprj\nset_option -top_module top_duo01\nrun all\n')
if __name__=='__main__':main()
