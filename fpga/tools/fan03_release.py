"""Standalone FAN03 verifier, simulation runner and Gowin rebuild entry.

No PC application dependency. Rebuild output is separate from frozen evidence.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'fpga/i2cfan03'
OUT = ROOT / 'board-test/fan03-rebuild'
MANIFEST = ROOT / 'board-test/I2C负Z独立加速度或急动度固件清单.json'
TESTS = ('tb_i2c_faults', 'tb_i2c_transport', 'tb_i2c_host', 'tb_i2c_path',
         'tb_i2c_guard', 'tb_calibration_quality', 'tb_ui_keys', 'tb_ui_pages',
         'tb_video_hdmi', 'tb_ui_silent_top', 'tb_fan_control', 'tb_fan_keys',
         'tb_z_strike', 'tb_z_reports', 'tb_z_repeated')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify():
    data = json.loads(MANIFEST.read_text(encoding='utf8'))
    assert sha(ROOT / data['firmware']) == data['sha256'], 'bitstream mismatch'
    for name, digest in data['source_sha256'].items():
        assert sha(WORK / name) == digest, f'source mismatch: {name}'
    render = data['render_validation']
    for name, digest in render['source_sha256'].items():
        assert sha(ROOT / name) == digest, f'render source mismatch: {name}'
    for name, digest in render['frames_sha256'].items():
        assert sha(ROOT / 'board-test/i2c-fan03' / name) == digest, name
    assert len(data['simulations']) == 15
    assert all(result['passed'] for result in data['simulations'].values())
    assert data['timing_violations'] == {'setup': 0, 'hold': 0}
    assert data['physical_downward_strikes_verified'] is False
    print('PASS frozen FAN03 source/ROM/constraints/bitstream/34 rasters; physical test pending')


def simulator_command(top, files, output):
    if shutil.which('iverilog') and shutil.which('vvp'):
        return (['iverilog', '-g2012', '-s', top, '-o', str(output)]
                + [str(p) for p in files]), ['vvp', str(output)]
    if os.name != 'nt' or not shutil.which('wsl'):
        raise RuntimeError('Install Icarus Verilog (iverilog + vvp), or WSL Ubuntu with Icarus')
    def linux(p):
        return '/mnt/' + p.drive[0].lower() + str(p)[2:].replace('\\', '/')
    # Paths contain no shell substitutions; quote every filesystem argument.
    def quote(s):
        return "'" + s.replace("'", "'\"'\"'") + "'"
    compile_line = 'cd ' + quote(linux(WORK)) + ' && iverilog -g2012 -s ' + top
    compile_line += ' -o ' + quote(linux(output))
    compile_line += ' ' + ' '.join(quote(linux(p)) for p in files)
    run_line = 'cd ' + quote(linux(WORK)) + ' && vvp ' + quote(linux(output))
    prefix = ['wsl', '-d', 'Ubuntu', '-e', 'bash', '-lc']
    return prefix + [compile_line], prefix + [run_line]


def check():
    OUT.mkdir(parents=True, exist_ok=True)
    files = [p for p in sorted((WORK / 'rtl').glob('*.v')) if p.name != 'video_pll_125.v']
    files += sorted((WORK / 'tb').glob('*.sv')) + [ROOT / 'fpga/tb/tb_video_hdmi.sv']
    snapshot = {str(p): sha(p) for p in files}
    def run(top):
        executable = OUT / (top + '.vvp')
        compile_cmd, run_cmd = simulator_command(top, files, executable)
        compiled = subprocess.run(compile_cmd, cwd=WORK, capture_output=True)
        ran = subprocess.run(run_cmd, cwd=WORK, capture_output=True) if not compiled.returncode else compiled
        output = ran.stdout.decode('utf8', errors='replace')
        errors = compiled.stderr.decode('utf8', errors='replace')
        if ran is not compiled:
            errors += ran.stderr.decode('utf8', errors='replace')
        (OUT / (top + '.log')).write_text(output + '\n' + errors, encoding='utf8')
        result = {'passed': ran.returncode == 0 and 'TB_PASS' in output,
                  'exit_code': ran.returncode}
        print(top, result, flush=True)
        return top, result
    with ThreadPoolExecutor(max_workers=5) as pool:
        results = dict(pool.map(run, TESTS))
    assert snapshot == {str(p): sha(p) for p in files}, 'inputs changed during simulation'
    (OUT / 'simulation.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf8')
    assert all(r['passed'] for r in results.values()), 'see simulation logs'


def build(shell):
    executable = shell or shutil.which('gw_sh') or shutil.which('gw_sh.exe')
    if not executable:
        raise RuntimeError('Pass --gowin-shell with the installed Gowin gw_sh executable')
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='fan03-gowin-') as temporary:
        wrapper = Path(temporary) / 'run.tcl'
        wrapper.write_text('if {[catch {source build.tcl} error]} {puts stderr $error;exit 1}\nexit 0\n')
        with (OUT / 'gowin-build.log').open('w', encoding='utf8') as log:
            result = subprocess.run([executable, str(wrapper)], cwd=WORK,
                                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    assert result.returncode == 0, 'see board-test/fan03-rebuild/gowin-build.log'
    generated = WORK / 'impl/pnr/tanglab_i2c_fan03.fs'
    assert generated.is_file(), 'Gowin did not generate bitstream'
    print('Rebuilt:', generated, 'SHA256:', sha(generated))
    print('Frozen fpga/bitstream file has not been overwritten; inspect new timing/pin reports.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['verify', 'check', 'build'])
    parser.add_argument('--gowin-shell')
    args = parser.parse_args()
    if args.action == 'verify':
        verify()
    elif args.action == 'check':
        check()
    else:
        build(args.gowin_shell)
