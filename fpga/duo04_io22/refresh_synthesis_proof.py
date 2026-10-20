"""Bind proof to an implicit synthesis inside run pnr, with unchanged inputs.

Run only after the actual routing log has confirmed netlist ingestion. Never
changes HDL/constraints, launches EDA, or accepts timing/bitstreams.
"""
from pathlib import Path
import datetime
import hashlib
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent
NAME='tanglab_duo04_io22'
V=ROOT/'validation'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')

def refresh():
    snapshot=read(V/'source_before_build.json')
    assert all(sha(ROOT/n)==h for n,h in snapshot['sha256'].items()), 'Source changed'
    net=ROOT/'impl/gwsynthesis'/(NAME+'.vg')
    log=net.with_suffix('.log')
    raw=log.read_text(errors='replace')
    invocation=datetime.datetime.fromisoformat(snapshot['timestamp']).timestamp()
    assert net.stat().st_mtime>=invocation, 'No implicit synthesis after invocation'
    assert 'GowinSynthesis finish' in raw and not re.search(r'^.*\bERROR\b',raw,re.M)
    pnr=ROOT/'impl/pnr'
    plog=pnr/(NAME+'.log')
    route_log=plog.read_text(errors='replace')
    assert 'Parsing netlist file' in route_log and 'completed' in route_log
    assert str(net).lower() in route_log.lower(), 'Routing used a different netlist path'
    command=(pnr/'cmd.do').read_text(errors='replace')
    assert re.search(r'-route_option\s+'+str(snapshot['expected_route_option'])+r'\b',command)
    previous=snapshot['reused_netlist_sha256'];actual=sha(net)
    snapshot['tool_invocation_started_at']=snapshot['timestamp']
    snapshot['synthesis_started_at']=snapshot['timestamp']
    snapshot['timestamp']=datetime.datetime.fromtimestamp(plog.stat().st_ctime).astimezone().isoformat()
    snapshot['reused_netlist_sha256']=actual
    snapshot['implicit_synthesis_before_pnr']=True
    synthesis=dict(snapshot,timestamp=snapshot['synthesis_started_at'])
    synthesis.pop('reused_netlist_sha256',None)
    write(V/'synthesis_before_build.json',synthesis)
    write(V/'source_before_build.json',snapshot)
    reuse=read(V/'netlist_reuse.json')
    reuse.update(reused_netlist_sha256=actual,synthesis_started_at=snapshot['synthesis_started_at'],
                 previous_netlist_sha256=previous,implicit_synthesis_before_pnr=True)
    write(V/'netlist_reuse.json',reuse)
    subprocess.check_call([sys.executable,'-X','utf8',str(ROOT/'check_imu_pads.py')],cwd=ROOT)
    xml=net.with_name(NAME+'_syn_rsc.xml')
    assert xml.stat().st_mtime>=net.stat().st_mtime, 'Resource report predates actual netlist'
    resource=ET.parse(xml).getroot()
    def attrs(name):return next(dict(n.attrib) for n in resource.iter() if n.attrib.get('name')==name)
    write(V/'synthesis_resources.json',{'scope':'actual implicit synthesis used by routed candidate, not routed resources',
        'source_snapshot_sha256':sha(V/'synthesis_before_build.json'),'report_sha256':sha(xml),
        'whole_design':dict(resource.attrib),'scheduler':attrs('scheduler'),'display':attrs('display'),
        'synthesis_reused_RTL_unchanged':True,'implicit_synthesis_before_pnr':True})
    options=read(V/'build_options.json')
    options.update(synthesis_skipped=False,implicit_synthesis_before_pnr=True,
                   flow='run pnr automatically recompiled identical sources; evidence rebound to actual netlist',
                   started_at=snapshot['timestamp'],tool_invocation_started_at=snapshot['tool_invocation_started_at'],
                   actual_command_sha256=sha(pnr/'cmd.do'))
    write(V/'build_options.json',options)
    evidence={'status':'PASS','sources_unchanged':True,
        'previous_netlist_sha256':previous,'actual_netlist_sha256':actual,
        'routed_netlist_path_confirmed':True,'six_open_drain_pads_rechecked':True,
        'actual_pnr_started_at':snapshot['timestamp'],'timing_accepted':False}
    write(V/'implicit_synthesis.json',evidence)
    # The already-running publisher includes this diagnostic evidence folder.
    write(V/'timing-attempt04/implicit_synthesis.json',evidence)
    print('PASS: unchanged sources, actual routed netlist, fresh resources and all six pad drivers rebound')

if __name__=='__main__':refresh()
