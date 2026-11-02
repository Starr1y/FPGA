"""Offline regression; --baseline replays the expected original RTL failure."""
from pathlib import Path
import argparse, subprocess, xml.etree.ElementTree as ET, json, os, sys, shutil, hashlib, datetime
a=argparse.ArgumentParser()
a.add_argument('--icarus-bin',default=os.environ.get('TANGLAB_IVERILOG_BIN',''))
a.add_argument('--baseline',action='store_true')
a.add_argument('--timeout',type=int,default=1200,help='Simulation limit per bench in seconds')
a.add_argument('tests',nargs='*')
args=a.parse_args()
p=Path(__file__).resolve().parent
iv=str(Path(args.icarus_bin)/'iverilog.exe') if args.icarus_bin else shutil.which('iverilog')
if not iv:raise SystemExit('Specify --icarus-bin or add Icarus to PATH')
vvp=str(Path(iv).with_name('vvp.exe'))
os.environ['PATH']=str(Path(iv).parent)+os.pathsep+os.environ['PATH']
out=p/'validation';out.mkdir(exist_ok=True)
files=[f.attrib['path'] for f in ET.parse(p/'tanglab_duo04_score27_routefix2.gprj').iter('File') if f.attrib.get('type')=='file.verilog']
files += [str(f.relative_to(p)) for f in (p/'tb/reference').glob('*.v')]
tests=args.tests or (['tb_static_pose_guard'] if args.baseline else ['tb_imu_uart_stream','tb_uart_hand','tb_static_pose_guard','tb_motion_trigger_paths','tb_stable25_zone','tb_stable26_zones','tb_stable26_hand','tb_stable26_top','tb_pose_axes','tb_prehit_snapshot','tb_report_backpressure','tb_wrist_gesture','tb_wrist_voice'])
flags=['-B',str(Path(iv).parent.parent/'lib/ivl'),'-g2012','-DTANG_SIM','-I.']
prefix='baseline_' if args.baseline else ''
if args.baseline:
    # Replace just this source in the compiler list; never rewrite candidate RTL.
    files=['validation/gesture_control_before.v' if f=='rtl/gesture_control.v' else f for f in files]
    flags+=['-DMOTIONFIX_BASELINE']
results={}
for t in tests:
    name=prefix+t
    test_flags=[v for v in flags if v!='-DTANG_SIM'] if t=='tb_pixel_reset_bridge' else flags
    command=[iv,*test_flags,'-s',t,'-o',str(out/(name+'.vvp')),*files,'tb/'+t+'.sv']
    c=subprocess.run(command,cwd=p,capture_output=True,text=True,errors='replace',timeout=180)
    (out/(name+'-compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8')
    result={'compile_exit':c.returncode,'compile_command':command,
            'recorded_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'testbench_sha256':hashlib.sha256((p/'tb'/(t+'.sv')).read_bytes()).hexdigest(),
            'input_manifest_sha256':hashlib.sha256((p/'INPUT_MANIFEST.json').read_bytes()).hexdigest()}
    if c.returncode==0:
        with (out/(name+'.log')).open('w',encoding='utf-8') as log:
            try:
                c=subprocess.run([vvp,'-i',str(out/(name+'.vvp'))],cwd=p,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
                exit_code=c.returncode
            except subprocess.TimeoutExpired:exit_code='TIMEOUT'
        simulation=(out/(name+'.log')).read_text(encoding='utf-8',errors='replace')
        result.update(exit=exit_code,passed=exit_code==0 and 'TB_PASS' in simulation)
        result['log_sha256']=hashlib.sha256((out/(name+'.log')).read_bytes()).hexdigest()
        print(name,exit_code,simulation[-1000:],flush=True)
    else:print(name,'COMPILE_FAILED',c.stderr[-2000:],flush=True)
    results[t]=result
    (out/(name+'-result.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
(out/(prefix+'test_results.json')).write_text(json.dumps(results,indent=2),encoding='utf-8')
sys.exit(0 if all(v.get('passed') for v in results.values()) else 1)
