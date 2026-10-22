"""Read saved implementation evidence only. Does not run EDA or Programmer."""
from pathlib import Path
import datetime, hashlib, html, json, re, sys

ROOT = Path(__file__).resolve().parent
PNR = ROOT / 'impl/pnr'
NAME = 'tanglab_duo04_ui23'
if not (PNR/(NAME+'_tr_content.html')).exists() and (ROOT/'reports/pnr').exists():
    PNR = ROOT/'reports/pnr'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def clean(s):
    return ' '.join(html.unescape(re.sub('<[^>]*>', ' ', s)).split())

result = {'project': 'TangLab UI23', 'base_commit': '554124f',
          'hardware_test': 'NOT RUN', 'starts_eda_or_programmer': False}
snapshot = json.loads((ROOT/'validation/source_before_build.json').read_text(encoding='utf-8'))
result['sources_unchanged'] = all((ROOT/p).is_file() and sha(ROOT/p)==h for p,h in snapshot['sha256'].items())
result['netlist_provenance_verified'] = False
if 'reused_netlist_sha256' not in snapshot:
    net = ROOT/'impl/gwsynthesis'/(NAME+'.vg')
    synlog=net.with_suffix('.log')
    route=PNR/(NAME+'.log')
    pads=ROOT/'validation/imu_open_drain_netlist.json'
    started=datetime.datetime.fromisoformat(snapshot['timestamp']).timestamp()
    if net.exists() and synlog.exists() and route.exists() and pads.exists():
        syntext=synlog.read_text(errors='replace')
        route_text=route.read_text(errors='replace').replace('\\','/').lower()
        padproof=json.loads(pads.read_text(encoding='utf-8'))
        result['netlist_provenance_verified']=(min(net.stat().st_mtime,synlog.stat().st_mtime)>=started and
            'GowinSynthesis finish' in syntext and not re.search(r'^.*\bERROR\b',syntext,re.M) and
            net.as_posix().lower() in route_text and 'parsing netlist file' in route_text and
            padproof['status']=='PASS' and padproof['netlist_sha256']==sha(net))
    elif not net.exists():
        # Published releases retain the verified synthesis/input fingerprint
        # and raw logs, not a second 20MB generated netlist. Local builds
        # always take the direct netlist branch above.
        provenance=ROOT/'validation/synthesis_provenance.json'
        archived_syn=ROOT/'reports/synthesis'/(NAME+'.log')
        if provenance.exists() and archived_syn.exists() and pads.exists() and route.exists():
            proof=json.loads(provenance.read_text(encoding='utf-8'))
            padproof=json.loads(pads.read_text(encoding='utf-8'))
            route_text=route.read_text(errors='replace').replace('\\','/').lower()
            syntext=archived_syn.read_text(errors='replace')
            result['netlist_provenance_verified']=(proof['status']=='PASS' and
                proof['source_snapshot_sha256']==sha(ROOT/'validation/source_before_build.json') and
                proof['synthesis_log_sha256']==sha(archived_syn) and
                proof['synthesized_inputs']==snapshot['sha256'] and
                proof['netlist_sha256']==padproof['netlist_sha256'] and padproof['status']=='PASS' and
                all((ROOT/n).exists() and sha(ROOT/n)==h for n,h in proof.get('supplemental_inherited_root_rom_sha256',{}).items()) and
                proof['netlist_absolute_path'].replace('\\','/').lower() in route_text and
                'parsing netlist file' in route_text and 'GowinSynthesis finish' in syntext and
                not re.search(r'^.*\bERROR\b',syntext,re.M))
            result['provenance_scope']='archived verified input/netlist fingerprint and raw synthesis/routing logs'
if 'reused_netlist_sha256' in snapshot:
    reuse=json.loads((ROOT/'validation/netlist_reuse.json').read_text(encoding='utf-8'))
    pads=json.loads((ROOT/'validation/imu_open_drain_netlist.json').read_text(encoding='utf-8'))
    rtl={n:h for n,h in snapshot['sha256'].items() if n.startswith('rtl/')}
    result['netlist_provenance_verified'] = (rtl==reuse['rtl_hashes'] and
        snapshot['sha256']['tanglab_duo04_ui23.gprj']==reuse['old_sources_sha256']['tanglab_duo04_ui23.gprj'] and
        snapshot['reused_netlist_sha256']==reuse['reused_netlist_sha256']==pads['netlist_sha256'])
    netlist=ROOT/'impl/gwsynthesis'/(NAME+'.vg')
    if netlist.exists():
        result['netlist_provenance_verified'] &= sha(netlist)==snapshot['reused_netlist_sha256']
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
    started = datetime.datetime.fromisoformat(snapshot['timestamp']).timestamp()
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
    result['routing_options_match'] = result['route_option']==snapshot.get('expected_route_option',1)
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
    result['status'] = 'IMPLEMENTED, BOARD VALIDATION PENDING' if (result['sources_unchanged'] and result['netlist_provenance_verified'] and
        result['bitstream_generated'] and not result['errors'] and result['setup_hold_zero'] and
        result['report_is_from_current_build'] and result['routing_options_match'] and result['core_pixel_frequencies_met'] and result['audio_pins_match']) else 'CHECK FAILED'
    if bit.exists():
        result.update(bitstream_sha256=sha(bit), bitstream_size=bit.stat().st_size)
    result['timing_report_sha256'] = sha(report)
manifest_path=ROOT/'FIRMWARE.json'
if manifest_path.exists():
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    result['manifest_matches']=(manifest['source_snapshot_sha256']==sha(ROOT/'validation/source_before_build.json') and
        manifest['synthesis_provenance_sha256']==sha(ROOT/'validation/synthesis_provenance.json') and
        bit.exists() and sha(bit)==manifest['bitstream']['sha256'] and
        all((ROOT/n).exists() and sha(ROOT/n)==h for n,h in manifest['reports'].items()))
    if not result['manifest_matches'] and result['status']=='IMPLEMENTED, BOARD VALIDATION PENDING':result['status']='CHECK FAILED'
    ui_path=ROOT/'validation/ui23_tests.json'
    address_path=ROOT/'validation/ui23_address.json'
    ui=json.loads(ui_path.read_text(encoding='utf-8'))
    address=json.loads(address_path.read_text(encoding='utf-8'))
    result['ui_address_evidence_matches']=(sha(ui_path)==manifest['ui_tests_sha256'] and
        sha(address_path)==manifest['address_tests_sha256'] and ui['status']=='PASS' and
        ui['source_snapshot_sha256']==sha(ROOT/'validation/source_before_build.json') and
        ui['full_raster_scenes']==14 and address['status']=='PASS' and address['checks']==16384 and
        address['rtl_sha256']==sha(ROOT/'rtl/duo04_panel.v') and
        all(sha(ROOT/'validation'/(n+'.log'))==h for n,h in ui['test_logs'].items()))
    if 'reuse_proof_sha256' in ui:
        reuse_path=ROOT/'validation/ui_test_reuse.json'
        reuse=json.loads(reuse_path.read_text(encoding='utf-8'))
        original_snapshot=ROOT/'validation/original_source_before_build.json'
        original_tests=ROOT/'validation/original_ui23_tests.json'
        old=json.loads(original_snapshot.read_text(encoding='utf-8'))
        old_ui=json.loads(original_tests.read_text(encoding='utf-8'))
        result['ui_reuse_matches']=(reuse['status']=='PASS' and sha(reuse_path)==ui['reuse_proof_sha256'] and
            sha(original_snapshot)==reuse['original_snapshot_sha256']==old_ui['source_snapshot_sha256'] and
            sha(original_tests)==reuse['original_tests_sha256'] and
            reuse['selected_snapshot_sha256']==sha(ROOT/'validation/source_before_build.json') and
            reuse['identical_inputs']==old['sha256'] and
            set(snapshot['sha256'])-set(old['sha256'])=={'pnr_only.tcl'} and
            all(snapshot['sha256'][n]==h and sha(ROOT/n)==h for n,h in old['sha256'].items()) and
            reuse['test_logs']==old_ui['test_logs']==ui['test_logs'])
        result['ui_address_evidence_matches'] &= result['ui_reuse_matches']
    if 'rebuild_scripts' in manifest:
        result['selected_rebuild_scripts_match']=all((ROOT/n).exists() and sha(ROOT/n)==h for n,h in manifest['rebuild_scripts'].items())
        result['manifest_matches'] &= result['selected_rebuild_scripts_match']
    if 'routing_selection_sha256' in manifest:
        selection_path=ROOT/'validation/routing_selection.json'
        selection=json.loads(selection_path.read_text(encoding='utf-8'))['selection']
        result['routing_selection_matches']=(sha(selection_path)==manifest['routing_selection_sha256'] and
            selection['selected_route_option']==manifest['selected_route_option']==result['route_option'] and
            selection['selected_bitstream_sha256']==manifest['bitstream']['sha256'])
        result['manifest_matches'] &= result['routing_selection_matches']
    if not result['ui_address_evidence_matches'] or not result['manifest_matches']:
        result['status']='CHECK FAILED'
print(json.dumps(result,ensure_ascii=False,indent=2))
sys.exit(0 if result['status']=='IMPLEMENTED, BOARD VALIDATION PENDING' else 1)
