"""Targeted production audio/UART simulation and real-frame decoder checks."""
from pathlib import Path
import argparse,subprocess,sys,json,struct,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from lab_engine import LabEngine
import lab_protocol as P

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',required=True);args=p.parse_args()
    project=ROOT/'fpga/duo02-mouse';out=Path(args.out).resolve();out.mkdir(parents=True,exist_ok=False)
    # ROM paths are relative to the simulation working directory.
    import shutil
    (out/'rtl').mkdir()
    for f in (project/'rtl').glob('*.hex'):shutil.copy2(f,out/'rtl'/f.name)
    def run(tool,args,timeout=600):
        cmd=[str(Path('D:/FPGA_VIVADO/2025.2/Vivado/bin')/(tool+'.bat')),*map(str,args)]
        with (out/(tool+'.log')).open('w',encoding='utf-8') as log:
            result=subprocess.run(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        text=(out/(tool+'.log')).read_text(encoding='utf-8',errors='replace')
        print(tool,result.returncode,text[-1000:],flush=True)
        if result.returncode:raise RuntimeError(tool+' failed')
        return text
    names=['dual_note_map','dual_voice_scheduler','dual_audio_core','two_hand_synth','two_hand_event_queue',
           'timbre_presets','sine_lut','instrument_waves','fm_limits','stereo_fx','stereo_output_path',
           'sine_calibrator','stereo_makeup_limiter','pt8211_output','framing','uart','video_duo_hdmi','top_duo02_mouse']
    sources=[project/'rtl'/(n+'.v') for n in names]
    run('xvlog',['--sv','-d','TANG_SIM',*sources,project/'tb/tb_mouse_uart.sv'])
    run('xelab',['tb_mouse_uart','-s','mouse_sim','--timescale','1ns/1ps'])
    (out/'run.tcl').write_text('run all\nquit\n')
    text=run('xsim',['mouse_sim','-tclbatch','run.tcl'])
    if 'TB_PASS' not in text:raise RuntimeError('RTL did not pass')
    wire=bytes.fromhex((out/'wire.hex').read_text());frames=P.Parser().feed(wire)
    parser=P.Parser();parser.feed(wire);assert parser.errors==0
    e=LabEngine();captures=[];voices=[]
    for f in frames:
        before=e.audio_revision;e.frame(f)
        if e.audio_revision>before:captures.append((e.audio.copy(),dict(e.audio_metadata)));voices.append(e.voice_audio.copy())
    assert e.device=='DUO02-MOUSE 1.3' and len(captures)==5
    assert [a.shape for a,m in captures]==[(512,5),(512,5),(2048,5),(512,5),(512,5)]
    assert [m['event_id'] for a,m in captures]==[101,201,0,0,0]
    for index,(a,m) in enumerate(captures[:3]):
        assert np.array_equal(a[:,4],(a[:,2].astype(int)+a[:,3].astype(int))//2)
        # Bypass post-gain PCM must exactly match aligned dry stereo samples.
        scaled=a[32:,:2].astype(int)*64
        assert np.array_equal(a[32:,2:4],(scaled+np.where(scaled<0,127,128))>>8)
        np.savetxt(out/f'capture-{index+1}.csv',a,fmt='%d',delimiter=',',header='dry_left,dry_right,post_left,post_right,post_mix',comments='')
    assert [v.shape for v in voices]==[(512,2),(512,3),(2048,3),(512,0),(512,3)]
    assert captures[3][1]['calibration'] and np.max(abs(captures[3][0][:,2]))>1000
    assert not np.any(captures[4][0]) and not np.any(voices[4])
    assert captures[0][1]['monitor_voices']==[0,16] and captures[1][1]['monitor_voices']==[0,16,31]
    assert np.array_equal(captures[0][0][:,0],voices[0][:,0].astype(int)>>4)
    assert np.array_equal(captures[1][0][:,1],voices[1][:,1].astype(int)>>4)
    assert np.any(voices[0][:,0]) and not np.any(voices[0][:,1])
    assert np.any(captures[0][0][:,0]) and not np.any(captures[0][0][:,1])
    assert np.any(captures[1][0][:,1]) and not np.any(captures[1][0][:,0])
    a=captures[2][0];freq=np.fft.rfftfreq(len(a),1/48000);peak=float(freq[np.argmax(abs(np.fft.rfft(a[:,1]*np.hanning(len(a)))) )])
    assert abs(peak-261.6256)<48000/len(a)*2
    statuses=[f.payload for f in frames if f.kind==136]
    assert any(struct.unpack_from('<I',b,32)[0]==0xffffffff for b in statuses),'32 active voices not observed'
    assert all(struct.unpack_from('<I',b,44)[0]==0 for b in statuses),'underflow'
    result=dict(result='PASS',source='RTL simulation, not physical',captures=[dict(shape=list(a.shape),metadata=m) for a,m in captures],crc_errors=parser.errors,peak_hz=peak,
                uart_baud=921600,sample_rate=48000,packet_gap_simulation_us=100,packet_gap_hardware_ms=10,pt8211_checked=True,tmds_primitives_simulated=False)
    (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS actual UART frames, onset IDs, 512/2048, exact dry/post alignment, stereo isolation, mix, FFT and 32 Voice')
    e.close()
if __name__=='__main__':main()
