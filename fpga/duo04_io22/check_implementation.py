"""Read saved implementation evidence only. Does not run EDA or Programmer."""
from pathlib import Path
import hashlib, html, json, re, sys

ROOT = Path(__file__).resolve().parent
PNR = ROOT / 'impl/pnr'
NAME = 'tanglab_duo04_io22'
if not (PNR/(NAME+'_tr_content.html')).exists() and (ROOT/'reports/pnr').exists():
    PNR = ROOT/'reports/pnr'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def clean(s):
    return ' '.join(html.unescape(re.sub('<[^>]*>', ' ', s)).split())

result = {'project': 'DUO04-LIVE 2.2', 'base_commit': 'e9230db',
          'hardware_test': 'NOT RUN', 'starts_eda_or_programmer': False}
snapshot = json.loads((ROOT/'validation/source_before_build.json').read_text(encoding='utf-8'))
result['sources_unchanged'] = all((ROOT/p).is_file() and sha(ROOT/p)==h for p,h in snapshot['sha256'].items())
log = PNR / (NAME+'.log')
bit = PNR / (NAME+'.fs')
if not bit.exists():
    bit = ROOT/'bitstream'/(NAME+'.fs')
report = PNR / (NAME+'_tr_content.html')
if not log.exists() or not report.exists():
    result.update(status='NOT FINISHED', bitstream_generated=False)
else:
    text = log.read_text(errors='replace')
    result['errors'] = re.findall(r'^.*\bERROR\b.*$', text, re.M)
    result['clock_warnings'] = re.findall(r'^.*PR1014.*$', text, re.M)
    result['bitstream_generated'] = bit.exists() and 'Bitstream generation completed' in text
    raw = report.read_text(errors='replace')
    section = raw.split('Total Negative Slack Summary:',1)[-1].split('Timing Details',1)[0]
    rows = []
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>',section,re.S):
        cells = [clean(c) for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S)]
        if cells: rows.append(cells)
    result['negative_slack_rows'] = rows
    timed = [r for r in rows if len(r)>=4 and r[1] in ('Setup','Hold')]
    result['setup_hold_zero'] = bool(timed) and all(float(r[2])==0 and int(r[3])==0 for r in timed)
    pins = PNR/(NAME+'.pin.html')
    expected={'i2s_bck':'C14','i2s_ws':'B13','i2s_dout':'C13',
              'hp_bck':'Y17','hp_ws':'AB17','hp_din':'AA16'}
    pin_rows={}
    if pins.exists():
        for row in re.findall(r'<tr[^>]*>(.*?)</tr>',pins.read_text(errors='replace'),re.S):
            cells=[clean(c) for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S)]
            if cells and cells[0] in expected and len(cells)>=10:
                pin_rows[cells[0]]={'pin':cells[2].split('/')[0],
                                  'direction':cells[4],'io_type':cells[7], 'pull':cells[9]}
    result['audio_pin_rows']=pin_rows
    result['audio_pins_match']=all(name in pin_rows and pin_rows[name]['pin']==pin and
        pin_rows[name]['direction']=='out' and pin_rows[name]['io_type']=='LVCMOS33' and
        pin_rows[name]['pull']=='NONE' for name,pin in expected.items())
    result['status'] = 'IMPLEMENTED, BOARD VALIDATION PENDING' if (result['sources_unchanged'] and
        result['bitstream_generated'] and not result['errors'] and result['setup_hold_zero'] and
        result['audio_pins_match']) else 'CHECK FAILED'
    if bit.exists():
        result.update(bitstream_sha256=sha(bit), bitstream_size=bit.stat().st_size)
    result['timing_report_sha256'] = sha(report)
print(json.dumps(result,ensure_ascii=False,indent=2))
sys.exit(0 if result['status']=='IMPLEMENTED, BOARD VALIDATION PENDING' else 1)
