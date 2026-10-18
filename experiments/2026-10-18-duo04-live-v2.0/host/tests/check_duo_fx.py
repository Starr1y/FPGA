from pathlib import Path
import sys,subprocess
root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False)
rtl=root/'fpga/duo02-mouse/rtl';tb=root/'fpga/duo02-mouse/tb/tb_stereo_output_path.sv'
def run(tool,args):
    with (out/(tool+'.log')).open('w') as f:
        p=subprocess.run([f'D:/FPGA_VIVADO/2025.2/Vivado/bin/{tool}.bat',*map(str,args)],cwd=out,stdout=f,stderr=subprocess.STDOUT,timeout=300)
    text=(out/(tool+'.log')).read_text(errors='replace');assert p.returncode==0,text[-1800:]
    return text
run('xvlog',['--sv',rtl/'stereo_fx.v',rtl/'stereo_makeup_limiter.v',rtl/'stereo_output_path.v',rtl/'pt8211_output.v',tb])
run('xelab',['tb_stereo_output_path','-s','fx','--timescale','1ns/1ps'])
(out/'run.tcl').write_text('run all\nquit\n')
text=run('xsim',['fx','-tclbatch','run.tcl']);assert 'TB_PASS' in text,text[-1800:]
print('PASS production FX, 1/32 volume, delay impulse, stereo separation, history clear, reverb/chorus switches and PT8211')
