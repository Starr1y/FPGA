"""Freeze only a completed, checked build. Never launches EDA or Programmer."""
from pathlib import Path
import hashlib,json,shutil,stat,subprocess,sys,datetime

ROOT=Path(__file__).resolve().parent
NAME='tanglab_duo04_io22'
V=ROOT/'validation'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def copy_generated(src,dest):
    if dest.exists():dest.chmod(dest.stat().st_mode|stat.S_IWRITE)
    return shutil.copy2(src,dest)
tests=['serial_formats','mixed_latency','audio_latency','fan04_expression_200',
       'tb_ui21_controls','tb_ui21_encoder','tb_ui21_lesson','tb_ui21_stop',
       'tb_ui21_panel','tb_duo04_32','tb_io22_hello','tb_scheduler_pipeline','tb_io22_control_pipeline']
repair=V/'timing_repair.json'
if repair.exists():
    proof=json.loads(repair.read_text(encoding='utf-8'))
    assert proof['status'] in ('SIMULATION PASS; IMPLEMENTATION PENDING','SIMULATION AND IMPLEMENTATION PASS')
    assert all(sha(ROOT/n)==h for n,h in proof['tested_inputs'].items()), 'Repair inputs differ from tested sources'
    assert proof['test_count']==len(proof['tests']) and set(tests).issubset(proof['tests'])
    assert all(sha(V/(n+'.log'))==h for n,h in proof['tests'].items()), 'Repair log hashes changed'
    tests += [n for n in proof['tests'] if n not in tests]
records={}
for t in tests:
    p=V/(t+'.log')
    text=p.read_text(errors='replace')
    assert 'TB_PASS' in text and 'FATAL:' not in text,(t,'not finished/passed')
    records[t]={'sha256':sha(p),'pass_lines':[line for line in text.splitlines() if 'TB_PASS' in line]}
host=json.loads((V/'host_compat.json').read_text(encoding='utf-8-sig'))
assert host['status']=='PASS' and host['latest_host_interaction_enabled']
pad_proof=json.loads((V/'imu_open_drain_netlist.json').read_text(encoding='utf-8'))
assert pad_proof['status']=='PASS' and len(pad_proof['instances'])==6
assert pad_proof['netlist_sha256']==sha(ROOT/'impl/gwsynthesis'/(NAME+'.vg'))
checked=subprocess.run([sys.executable,str(ROOT/'check_implementation.py')],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
assert checked.returncode==0,checked.stdout+checked.stderr
implementation=json.loads(checked.stdout)
integration=json.loads((V/'integration.json').read_text(encoding='utf-8'))
integration.update(source_hashes_still_match_build_snapshot=implementation['sources_unchanged'],
                   implementation_status=implementation['status'],
                   build_options=json.loads((V/'build_options.json').read_text(encoding='utf-8')))
(V/'integration.json').write_text(json.dumps(integration,ensure_ascii=False,indent=2),encoding='utf-8')
if repair.exists():
    proof['status']='SIMULATION AND IMPLEMENTATION PASS'
    proof['implementation']=implementation
    proof['hardware_test']='NOT RUN'
    repair.write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
(V/'implementation.json').write_text(json.dumps(implementation,ensure_ascii=False,indent=2),encoding='utf-8')
bitdir=ROOT/'bitstream';bitdir.mkdir(exist_ok=True)
copy_generated(ROOT/'impl/pnr'/(NAME+'.fs'),bitdir/(NAME+'.fs'))
for sub in ['pnr','gwsynthesis']:
    src=ROOT/'impl'/sub;dest=ROOT/'reports'/sub;dest.mkdir(parents=True,exist_ok=True)
    for p in src.iterdir():
        if p.suffix in ('.html','.log','.txt') or p.name=='cmd.do':copy_generated(p,dest/p.name)
manifest={'version':'DUO04-LIVE 2.1+IO22','integration_revision':'2.2',
 'base_commit':'e9230dbd56654365d1219a0770a61b75a6a2a47a',
 'frozen_at':datetime.datetime.now().astimezone().isoformat(),
 'bitstream':f'bitstream/{NAME}.fs','bitstream_sha256':sha(bitdir/(NAME+'.fs')),
 'implementation':implementation,'hardware_test':'NOT RUN',
 'end_to_end_10ms_or_5ms_proven':False,'host_files_included':False}
selection=V/'routing-comparison/selection.json'
if selection.exists():
    selected=json.loads(selection.read_text(encoding='utf-8'))
    assert selected['status']=='SELECTED'
    assert selected['selected_route_option']==implementation['route_option']
    assert selected['selected_bitstream_sha256']==manifest['bitstream_sha256']
    manifest['routing_selection']={'report':'validation/routing-comparison/selection.json',
                                  'sha256':sha(selection),
                                  'selected_route_option':selected['selected_route_option']}
(ROOT/'FIRMWARE.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(V/'RESULT.json').write_text(json.dumps({'status':'DIGITAL CHECKS AND IMPLEMENTATION PASS; HARDWARE PENDING',
 'tests':records,'host_compat':host,'hardware_test':'NOT RUN',
 'latency_scope':'Independent digital simulation segments; not a physical end-to-end upper bound',
 'uart_scope':'Current HELLO tested at921600 with published host parser; full inherited teaching/capture UART regression NOT rerun to completion',
 'shtp_scope':'SH2 report sequence/timestamp continuity checked; inherited transport sequence_gaps semantics unchanged',
 'imu_open_drain_netlist':pad_proof,'implementation':implementation},ensure_ascii=False,indent=2),encoding='utf-8')
files=[p for p in ROOT.rglob('*') if p.is_file() and
       not any(x in p.relative_to(ROOT).parts for x in ('impl','__pycache__')) and
       p.suffix not in ('.vvp','.ppm','.csv','.hex')]
# ROM .hex are source inputs; only raw UART dumps in project root are omitted.
files += list((ROOT/'rtl').glob('*.hex'))
files=[p for p in files if p.name!='SHA256.txt' and not p.name.endswith('.compile.log') and p.name not in ('panel_debug.log','tb_io22_uart.log','tb_duo04_audio.log')]
(ROOT/'SHA256.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(ROOT).as_posix()}\n' for p in sorted(set(files))),encoding='utf-8')
print('FROZEN',manifest['bitstream_sha256'])
