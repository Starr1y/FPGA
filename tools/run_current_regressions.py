"""Portable Icarus replay; writes to a fresh directory, never frozen validation."""
from pathlib import Path
import argparse, datetime, json, os, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET

a = argparse.ArgumentParser()
a.add_argument('--iverilog-bin', default='')
a.add_argument('--output', help='New output directory; defaults to a temporary directory')
a.add_argument('--timeout', type=int, default=1200)
a.add_argument('tests', nargs='*')
args = a.parse_args()
p = Path(__file__).resolve().parents[1]/'fpga/current'
suffix = '.exe' if os.name == 'nt' else ''
iv = str((Path(args.iverilog_bin)/('iverilog'+suffix)).resolve()) if args.iverilog_bin else shutil.which('iverilog')
if not iv:
    raise SystemExit('Install Icarus or specify --iverilog-bin')
vvp = str(Path(iv).with_name('vvp'+suffix))
os.environ['PATH'] = str(Path(iv).parent)+os.pathsep+os.environ['PATH']
out = Path(args.output).resolve() if args.output else Path(tempfile.mkdtemp(prefix='tanglab-v14-'))
if args.output:
    out.mkdir(parents=True, exist_ok=False)
flags = ['-g2012','-DTANG_SIM','-I.']
ivlib = Path(iv).parent.parent/'lib/ivl'
if os.name == 'nt' and ivlib.is_dir():
    flags = ['-B',str(ivlib),*flags]
files = [x.attrib['path'] for x in ET.parse(p/'tanglab_duo04_score27_routefix2.gprj').iter('File') if x.attrib.get('type')=='file.verilog']
files += [str(x.relative_to(p)) for x in (p/'tb/reference').glob('*.v')]
tests = args.tests or ['tb_yforward_mpu_hand','tb_native_mpu_hand','tb_button_trigger','tb_pose_axes','tb_yforward_heading','tb_yforward_pins']
results = {}
print('OUTPUT', out, flush=True)
for test in tests:
    bench = p/'tb'/f'{test}.sv'
    if not bench.exists():
        bench = p/'validation'/f'{test}.sv'
    if not bench.is_file():
        raise SystemExit('Missing bench: '+test)
    command = [iv,*flags,'-s',test,'-o',str(out/(test+'.vvp')),*files,str(bench)]
    compilation = subprocess.run(command,cwd=p,capture_output=True,text=True,errors='replace',timeout=180)
    (out/(test+'-compile.log')).write_text(compilation.stdout+compilation.stderr,encoding='utf-8')
    result = {'compile_exit':compilation.returncode, 'passed':False,
              'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    if compilation.returncode == 0:
        with (out/(test+'.log')).open('w',encoding='utf-8') as log:
            try:
                run = subprocess.run([vvp,'-i',str(out/(test+'.vvp'))],cwd=p,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
                result['exit_code'] = run.returncode
            except subprocess.TimeoutExpired:
                result['exit_code'] = 'TIMEOUT'
        text = (out/(test+'.log')).read_text(encoding='utf-8',errors='replace')
        result['passed'] = result['exit_code']==0 and 'TB_PASS' in text
    results[test] = result
    print(test, 'PASS' if result['passed'] else 'FAIL', flush=True)
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
sys.exit(0 if all(x['passed'] for x in results.values()) else 1)
