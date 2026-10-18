"""Freeze only a completed, checked build. Never launches EDA or Programmer."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,datetime

ROOT=Path(__file__).resolve().parent
NAME='tanglab_duo04_io22'
V=ROOT/'validation'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
tests=['serial_formats','mixed_latency','audio_latency','fan04_expression_200',
       'tb_ui21_controls','tb_ui21_encoder','tb_ui21_lesson','tb_ui21_stop',
       'tb_ui21_panel','tb_duo04_32','tb_io22_hello']
records={}
for t in tests:
    p=V/(t+'.log')
    text=p.read_text(errors='replace')
    assert 'TB_PASS' in text and 'FATAL:' not in text,(t,'not finished/passed')
    records[t]={'sha256':sha(p),'pass_lines':[line for line in text.splitlines() if 'TB_PASS' in line]}
host=json.loads((V/'host_compat.json').read_text(encoding='utf-8-sig'))
assert host['status']=='PASS' and host['latest_host_interaction_enabled']
checked=subprocess.run([sys.executable,str(ROOT/'check_implementation.py')],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
assert checked.returncode==0,checked.stdout+checked.stderr
implementation=json.loads(checked.stdout)
(V/'implementation.json').write_text(json.dumps(implementation,ensure_ascii=False,indent=2),encoding='utf-8')
bitdir=ROOT/'bitstream';bitdir.mkdir(exist_ok=True)
shutil.copy2(ROOT/'impl/pnr'/(NAME+'.fs'),bitdir/(NAME+'.fs'))
for sub in ['pnr','gwsynthesis']:
    src=ROOT/'impl'/sub;dest=ROOT/'reports'/sub;dest.mkdir(parents=True,exist_ok=True)
    for p in src.iterdir():
        if p.suffix in ('.html','.log'):shutil.copy2(p,dest/p.name)
manifest={'version':'DUO04-LIVE 2.1+IO22','integration_revision':'2.2',
 'base_commit':'e9230dbd56654365d1219a0770a61b75a6a2a47a',
 'frozen_at':datetime.datetime.now().astimezone().isoformat(),
 'bitstream':f'bitstream/{NAME}.fs','bitstream_sha256':sha(bitdir/(NAME+'.fs')),
 'implementation':implementation,'hardware_test':'NOT RUN',
 'end_to_end_10ms_or_5ms_proven':False,'host_files_included':False}
(ROOT/'FIRMWARE.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(V/'RESULT.json').write_text(json.dumps({'status':'DIGITAL CHECKS AND IMPLEMENTATION PASS; HARDWARE PENDING',
 'tests':records,'host_compat':host,'hardware_test':'NOT RUN',
 'latency_scope':'Independent digital simulation segments; not a physical end-to-end upper bound',
 'uart_scope':'Current HELLO tested at921600 with published host parser; full inherited teaching/capture UART regression NOT rerun to completion',
 'shtp_scope':'SH2 report sequence/timestamp continuity checked; inherited transport sequence_gaps semantics unchanged',
 'implementation':implementation},ensure_ascii=False,indent=2),encoding='utf-8')
files=[p for p in ROOT.rglob('*') if p.is_file() and
       not any(x in p.relative_to(ROOT).parts for x in ('impl','__pycache__')) and
       p.suffix not in ('.vvp','.ppm','.csv','.hex')]
# ROM .hex are source inputs; only raw UART dumps in project root are omitted.
files += list((ROOT/'rtl').glob('*.hex'))
files=[p for p in files if p.name!='SHA256.txt' and not p.name.endswith('.compile.log') and p.name not in ('panel_debug.log','tb_io22_uart.log','tb_duo04_audio.log')]
(ROOT/'SHA256.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(ROOT).as_posix()}\n' for p in sorted(set(files))),encoding='utf-8')
print('FROZEN',manifest['bitstream_sha256'])
