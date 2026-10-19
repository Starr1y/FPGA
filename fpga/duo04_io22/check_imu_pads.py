"""Check the current synthesized IMU pad drivers. Never starts EDA or Programmer."""
from pathlib import Path
import datetime, hashlib, json, re

root=Path(__file__).resolve().parent
netlist=root/'impl/gwsynthesis/tanglab_duo04_io22.vg'
snapshot=json.loads((root/'validation/source_before_build.json').read_text(encoding='utf-8'))
assert netlist.stat().st_mtime>=datetime.datetime.fromisoformat(snapshot.get('synthesis_started_at',snapshot['timestamp'])).timestamp(), 'stale netlist'
if 'reused_netlist_sha256' in snapshot:
    assert hashlib.sha256(netlist.read_bytes()).hexdigest()==snapshot['reused_netlist_sha256'], 'reused netlist changed'
    reuse=json.loads((root/'validation/netlist_reuse.json').read_text(encoding='utf-8'))
    assert all(hashlib.sha256((root/n).read_bytes()).hexdigest()==h for n,h in reuse['rtl_hashes'].items()), 'RTL changed after synthesis'
text=netlist.read_text(errors='replace')
instances=[]
seen=set()
for kind,name,ports in re.findall(r'\b(IOBUF|TBUF)\s+(\S+)\s*\((.*?)\);',text,re.S):
    pad=re.search(r'\.(?:IO|O)\((imu_(?:scl|sda|rst_n)\[[01]\])\)',ports)
    if not pad:continue
    assert re.search(r'\.I\(GND\)',ports) and re.search(r'\.OEN\(',ports), (name,ports)
    assert pad.group(1) not in seen, ('multiple drivers',pad.group(1))
    seen.add(pad.group(1))
    instances.append({'kind':kind,'instance':name,'ports':ports.strip()})
assert seen=={f'imu_{signal}[{i}]' for signal in ('scl','sda','rst_n') for i in range(2)},seen
result={'status':'PASS','netlist_sha256':hashlib.sha256(netlist.read_bytes()).hexdigest(),'instances':instances}
(root/'validation/imu_open_drain_netlist.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('PASS: all six synthesized IMU pad drivers drive GND or release')
