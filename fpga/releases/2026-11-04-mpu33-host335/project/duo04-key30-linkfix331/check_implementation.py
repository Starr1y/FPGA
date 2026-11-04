"""Read saved implementation reports; never launches EDA or Programmer.
A report pass is not a verified source-to-bitstream release or board validation.
"""
from pathlib import Path
import hashlib,html,json,re,sys
ROOT=Path(__file__).resolve().parent
PNR=ROOT/'impl/pnr'
NAME='tanglab_duo04_key30_linkfix331'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def clean(s):return ' '.join(html.unescape(re.sub('<[^>]*>',' ',s)).split())
snapshot_path=ROOT/'validation/SOURCE_SHA256.json'
snapshot=json.loads(snapshot_path.read_text(encoding='utf8'))
result={'project':'GEST27','starts_eda_or_programmer':False,'hardware_test':'NOT RUN',
        'sources_unchanged':all((ROOT/p).is_file() and sha(ROOT/p)==h for p,h in snapshot.items()),
        'netlist_provenance_verified':False,
        'scope':'Report checks only. Confirm current source/netlist provenance, clock network, CDC and external interfaces manually.'}
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
    started = max((ROOT/p).stat().st_mtime for p in snapshot if (ROOT/p).exists())
    result['report_is_from_current_build'] = min(log.stat().st_mtime,
        report.stat().st_mtime,bit.stat().st_mtime if bit.exists() else 0) >= started
    section = raw.split('Total Negative Slack Summary:',1)[-1].split('Timing Details',1)[0]
    rows = []
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>',section,re.S):
        cells = [clean(c) for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S)]
        if cells: rows.append(cells)
    result['negative_slack_rows'] = rows
    timed = [r for r in rows if len(r)>=4 and r[1] in ('Setup','Hold')]
    expected_clocks = ['ref_clk'] + [f'main_pll/PLL_inst/CLKOUT{i}.default_gen_clk' for i in range(3)]
    result['setup_hold_zero'] = (len(timed)==8 and
        {(r[0],r[1]) for r in timed} == {(c,a) for c in expected_clocks for a in ('Setup','Hold')} and
        all(float(r[2])==0 and int(r[3])==0 for r in timed))
    frequencies = []
    freq_section = raw.split('Max Frequency Summary:',1)[-1].split('Total Negative Slack Summary:',1)[0]
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>',freq_section,re.S):
        cells = [clean(c) for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S)]
        if len(cells)>=4 and cells[1] in expected_clocks:
            frequencies.append({'clock':cells[1],
                'constraint_mhz':float(cells[2].split('(')[0]),
                'actual_fmax_mhz':float(cells[3].split('(')[0])})
    result['routed_frequencies'] = frequencies
    required = {expected_clocks[2]:25.0, expected_clocks[3]:50.0}
    result['core_pixel_frequencies_met'] = all(any(f['clock']==c and
        f['constraint_mhz']==hz and f['actual_fmax_mhz']>=hz for f in frequencies) for c,hz in required.items())
    result['timing_scope'] = 'Routed internal setup/hold; external I2S DAC and physical end-to-end latency NOT measured'
    command=PNR/'cmd.do'
    options=re.search(r'-route_option\s+(\d+)',command.read_text(errors='replace')) if command.exists() else None
    result['route_option'] = int(options.group(1)) if options else None
    result['routing_options_match'] = result['route_option'] in (1,2)
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
    result['status'] = 'REPORT CHECKS PASS; PROVENANCE AND BOARD PENDING' if (result['sources_unchanged'] and 
        result['bitstream_generated'] and not result['errors'] and result['setup_hold_zero'] and
        result['report_is_from_current_build'] and result['routing_options_match'] and result['core_pixel_frequencies_met'] and result['audio_pins_match']) else 'CHECK FAILED'
    if bit.exists():
        result.update(bitstream_sha256=sha(bit), bitstream_size=bit.stat().st_size)
    result['timing_report_sha256'] = sha(report)
print(json.dumps(result,ensure_ascii=False,indent=2))
sys.exit(0 if result['status']=='REPORT CHECKS PASS; PROVENANCE AND BOARD PENDING' else 2)
