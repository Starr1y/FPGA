"""Run self-checking RTL benches with XSim; preserve logs and raw UART evidence."""
import argparse,subprocess,sys,json
from pathlib import Path

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',required=True);p.add_argument('--vivado',default='D:/FPGA_VIVADO/2025.2/Vivado/bin');p.add_argument('--bench',default='tb_lab');a=p.parse_args()
    root=Path(__file__).resolve().parent;out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
    def run(tool,args):
        exe=Path(a.vivado)/(tool+'.bat');cmd=[str(exe),*map(str,args)]
        r=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
        text=r.stdout.decode(errors='replace');(out/(tool+'.log')).write_text(text,encoding='utf-8');print(text[-2500:])
        if r.returncode:raise RuntimeError(tool+' failed')
        return text
    run('xvlog',['--sv',*sorted((root/'rtl').glob('*.v')),root/'tb'/f'{a.bench}.sv'])
    run('xelab',[a.bench,'-s',a.bench+'_sim','--timescale','1ns/1ps'])
    (out/'run.tcl').write_text('run all\nquit\n')
    text=run('xsim',[a.bench+'_sim','-tclbatch','run.tcl'])
    if 'TB_PASS' not in text:raise RuntimeError('No TB_PASS')
    if a.bench=='tb_lab':
        sys.path.insert(0,str(root.parent));from lab_engine import LabEngine
        import numpy as np
        e=LabEngine();e.ingest(bytes.fromhex((out/'wire.hex').read_text()))
        assert e.device=='TangLab 1.3.1' and e.capabilities['piano_control']
        import lab_protocol as P,struct
        frames=P.Parser().feed(bytes.fromhex((out/'wire.hex').read_text()))
        acknowledgements={struct.unpack('<HB',f.payload)[0]:struct.unpack('<HB',f.payload)[1] for f in frames if f.kind==P.ACK}
        assert acknowledgements[20]==0 and acknowledgements[21]==2
        assert e.parser.errors==0 and e.audio is not None and e.audio.shape==(2048,5)
        assert [len(s['samples']) for s in e.audio_history]==[512,2048]
        for segment in e.audio_history:
            samples=segment['samples']
            assert np.array_equal(samples[:,:4].astype(int).sum(axis=1),samples[:,4])
        f=np.fft.rfftfreq(2048,1/e.fs);peaks=[]
        for i in range(4):
            peak=f[np.argmax(np.abs(np.fft.rfft(e.audio[:,i])))];peaks.append(float(peak))
            assert abs(peak-375*(i+1))<24
        assert np.max(np.abs(e.audio[:,:4].astype(int).sum(axis=1)-e.audio[:,4]))==0
        np.save(out/'rtl_capture.npy',e.audio)
        (out/'validation.json').write_text(json.dumps(dict(result='PASS',peaks_hz=peaks,shape=list(e.audio.shape),crc_errors=e.parser.errors),indent=2))
        print('PASS: RTL UART -> Python CRC/decoder -> five-channel FFT and exact mix');e.close()
if __name__=='__main__':main()
