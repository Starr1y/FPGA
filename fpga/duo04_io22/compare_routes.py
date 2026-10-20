"""Compare completed routes of the same netlist. Reads reports; never runs EDA."""
from pathlib import Path
import argparse
import hashlib
import html
import json
import re
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows(section):
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>', section, re.S):
        yield [' '.join(html.unescape(re.sub('<[^>]*>', ' ', c)).split())
               for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', row, re.S)]


def measure(root):
    root = Path(root)
    check = subprocess.run([sys.executable, '-X', 'utf8', str(root/'check_implementation.py')],
                           cwd=root, capture_output=True, text=True, encoding='utf-8')
    gate = json.loads(check.stdout)
    snapshot = json.loads((root/'validation/source_before_build.json').read_text(encoding='utf-8'))
    pnr = root/'impl/pnr'
    report = pnr/'tanglab_duo04_io22_tr_content.html'
    metrics = {'route_option': snapshot['expected_route_option'],
               'eligible': check.returncode == 0,
               'gate': gate,
               'netlist_sha256': snapshot['reused_netlist_sha256'],
               'implementation_inputs': {n: h for n, h in snapshot['sha256'].items()
                   if n.startswith('rtl/') or n.endswith(('.gprj', '.cst', '.sdc'))}}
    if not report.exists():
        return metrics
    raw = report.read_text(errors='replace')
    # The table reports worst paths first. Keep exact STA slack, not a rounded
    # Fmax-to-period conversion; the table can include cross-clock paths.
    for kind, end in [('Setup', 'Hold'), ('Hold', 'Recovery')]:
        section = raw.split(f'name="{kind}_Slack_Table"', 1)[-1].split(f'name="{end}_Slack_Table"', 1)[0]
        slacks = [float(r[1]) for r in rows(section)
                  if len(r) >= 9 and r[0].isdigit()]
        metrics[f'worst_{kind.lower()}_slack_ns'] = min(slacks) if slacks else None
    text = (pnr/'tanglab_duo04_io22.rpt.txt').read_text(errors='replace')
    resources = {}
    for name in ['Logic', 'Register', 'CLS', 'BSRAM', 'DSP']:
        match = re.search(r'^\s*'+name+r'\s*\|\s*([\d.]+)/([\d.]+)', text, re.M)
        if match:
            resources[name] = {'used': float(match[1]), 'capacity': float(match[2])}
    metrics['resources'] = resources
    metrics['phase_times'] = [r.strip() for r in text.splitlines()
                             if any(n in r for n in ['Total Placement:', 'Total Routing:', 'Total Time and Memory Usage:'])]
    metrics['report_sha256'] = sha(report)
    metrics['bitstream_sha256'] = gate.get('bitstream_sha256')
    return metrics


def choose(candidates, require_same_netlist=True):
    assert len(candidates) == 2 and {c['route_option'] for c in candidates} == {1, 2}
    if require_same_netlist:
        assert candidates[0]['netlist_sha256'] == candidates[1]['netlist_sha256'], 'Netlists differ'
    assert candidates[0]['implementation_inputs'] == candidates[1]['implementation_inputs'], 'RTL/constraints differ'
    eligible = [c for c in candidates if c['eligible']]
    for c in eligible:
        assert c.get('worst_setup_slack_ns') is not None, 'No setup slack table'
        assert c.get('worst_hold_slack_ns') is not None, 'No hold slack table'
        assert c['worst_setup_slack_ns'] >= 0 and c['worst_hold_slack_ns'] >= 0
        assert 'CLS' in c['resources'], 'No physical resource summary'
    # Correct operation is mandatory. Maximize worst setup slack (ns); on an
    # exact report-precision tie maximize hold slack, then minimize physical CLS.
    # A complete tie uses the device-default route2. Runtime does not outweigh
    # timing margin. Neither routing result establishes measured board power.
    best = max(eligible, key=lambda c: (c['worst_setup_slack_ns'],
               c['worst_hold_slack_ns'], -c['resources']['CLS']['used'],
               c['route_option'] == 2)) if eligible else None
    return {'status': 'SELECTED' if best else 'NO ACCEPTABLE ROUTE',
            'comparison_scope': 'SAME_NETLIST' if require_same_netlist else 'SAME_SOURCE_INDEPENDENT_SYNTHESES',
            'selected_route_option': best['route_option'] if best else None,
            'selected_bitstream_sha256': best['bitstream_sha256'] if best else None,
            'policy': 'All implementation gates must pass; maximize worst setup slack, then hold slack, then minimize CLS; exact tie chooses device-default route2.',
            'scope': ('Same netlist, RTL, ROM, project and constraints.' if require_same_netlist else
                      'Same RTL, ROM, project and constraints; each tool-generated netlist independently verified. Differences cannot be attributed to route option alone.')+' No hardware download or measured power/end-to-end latency.',
            'candidates': candidates}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('route2', type=Path)
    parser.add_argument('route1', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-resynthesis',action='store_true',help='Same RTL/ROM/project/constraints, each synthesized netlist independently verified')
    args = parser.parse_args()
    result = choose([measure(args.route2), measure(args.route1)],require_same_netlist=not args.allow_resynthesis)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if result['status'] == 'SELECTED' else 1)
