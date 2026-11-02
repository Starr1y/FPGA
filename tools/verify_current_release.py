"""Read-only verification of the published V14 sources, bitstream and evidence."""
from pathlib import Path
import hashlib, json, re, sys, xml.etree.ElementTree as ET, zipfile

root = Path(__file__).resolve().parents[1]
p = root/'fpga/current'
errors = []
sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()

def require(condition, message):
    if not condition:
        errors.append(message)

def check_files(base, mapping):
    for name, digest in mapping.items():
        f = base/name
        require(f.is_file(), 'Missing: '+str(f))
        if f.is_file():
            require(sha(f) == digest, 'SHA256 mismatch: '+str(f))

release = json.loads((p/'RELEASE_MANIFEST.json').read_text(encoding='utf-8'))
original = json.loads((p/'INPUT_MANIFEST.json').read_text(encoding='utf-8'))
check_files(p, release['files_sha256'])
check_files(p, original['files'])
require(sha(p/'INPUT_MANIFEST.json') == release['input_manifest_sha256'], 'Input manifest changed')
require(sha(p/release['bitstream']) == release['bitstream_sha256'], 'Bitstream mismatch')
require(release['source_unchanged'] is True, 'Release is not the frozen V14')
for f in ET.parse(p/'tanglab_duo04_score27_routefix2.gprj').iter('File'):
    name = f.attrib['path']
    require(not Path(name).is_absolute() and (p/name).is_file(), 'Project reference missing/nonportable: '+name)

top = (p/'rtl/top_duo04.v').read_text()
require(re.search(r'LEFT_DIRECT_MPU\s*=\s*1', top) and re.search(r'RIGHT_DIRECT_MPU\s*=\s*0', top), 'Unexpected sensor configuration')
require('test_gain<=8;' in top, 'V14 default volume is no longer 8; rebuild and publish as a new release')
e = json.loads((p/'validation/DIRECT_MPU_BUILD_EVIDENCE.json').read_text())
require(e['implementation_pass'] is True and e['unrouted_nets'] == 0, 'Implementation evidence failed')
require(not e['source_mismatches'] and not e['errors'], 'Original build input errors')
require(e['exception_review_passed'] and e['imu_pad_review']['passed'], 'CDC/pad review failed')
require(e['sta']['setup_violated_endpoints'] == e['sta']['hold_violated_endpoints'] == 0, 'Timing violations')
require(e['sta']['worst_setup_ns'] == release['setup_ns'] and e['sta']['worst_hold_ns'] == release['hold_ns'], 'STA metadata mismatch')
require(sha(p/'reports/pnr/tanglab_duo04_score27_routefix2.rpt.txt') == e['pnr_report_sha256'], 'PNR report mismatch')
with zipfile.ZipFile(p/'reports/synthesis-netlist.zip') as z:
    digest = hashlib.sha256(z.read('tanglab_duo04_score27_routefix2.vg')).hexdigest()
require(digest == e['netlist_sha256'], 'Original synthesized netlist mismatch')
for name in ('tb_yforward_mpu_hand','tb_native_mpu_hand','tb_button_trigger','tb_pose_axes'):
    result = json.loads((p/'validation'/f'{name}-result.json').read_text())
    require(result['passed'] and result['input_manifest_sha256'] == release['input_manifest_sha256'], 'Test input/result mismatch: '+name)
    require(result['log_sha256'] == sha(p/'validation'/f'{name}.log'), 'Test log changed: '+name)
pins = json.loads((p/'validation/tb_yforward_pins-result.json').read_text())
require(pins['passed'], 'Pin-level test failed')
check_files(p, pins['files_sha256'])
require('TB_PASS' in (p/'validation/yforward_heading.log').read_text(), 'Heading test has no pass record')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(json.dumps({'status':'PASS','release':release['release_id'],
 'verified_archive_files':len(release['files_sha256']), 'verified_frozen_inputs':len(original['files']),
 'setup_ns':release['setup_ns'],'hold_ns':release['hold_ns'],
 'bitstream_sha256':release['bitstream_sha256'],
 'hardware_status':release['hardware_validation'],
 'scope':'File/evidence verification; no new EDA build or board programming'},ensure_ascii=False,indent=2))
