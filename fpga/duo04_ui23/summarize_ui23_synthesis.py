"""Archive actual synthesis evidence. This never accepts timing or programs FPGA."""
from pathlib import Path
import json,hashlib,shutil,datetime,re,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parent;N='tanglab_duo04_ui23';V=R/'validation'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def summarize():
 snapshot=json.loads((V/'source_before_build.json').read_text(encoding='utf-8'))
 assert all(sha(R/n)==h for n,h in snapshot['sha256'].items()),'Frozen inputs changed'
 S=R/'impl/gwsynthesis';net=S/(N+'.vg');log=S/(N+'.log');xml=S/(N+'_syn_rsc.xml')
 started=datetime.datetime.fromisoformat(snapshot['timestamp']).timestamp()
 assert min(net.stat().st_mtime,log.stat().st_mtime,xml.stat().st_mtime)>=started,'Stale synthesis'
 text=log.read_text(errors='replace')
 assert 'GowinSynthesis finish' in text and not re.search(r'^.*\bERROR\b',text,re.M)
 pads=json.loads((V/'imu_open_drain_netlist.json').read_text(encoding='utf-8'))
 assert pads['status']=='PASS' and pads['netlist_sha256']==sha(net)
 out=R/'reports/synthesis';out.mkdir(parents=True,exist_ok=True)
 for p in S.iterdir():
  if p.suffix in ('.log','.xml','.html','.prj'):shutil.copy2(p,out/p.name)
 resource=ET.parse(xml).getroot()
 def total(key):return int(resource.attrib.get('T_'+key,'0').split('(')[0])
 extra={}
 for n in ('hello_wire.hex','io22_wire.hex'):
  p=R/n;assert p.exists() and p.stat().st_mtime<=started
  extra[n]=sha(p)
 proof={'status':'PASS','scope':'actual production synthesis; timing/hardware not implied',
  'source_snapshot_sha256':sha(V/'source_before_build.json'),'synthesized_inputs':snapshot['sha256'],
  'supplemental_inherited_root_rom_sha256':extra,
  'root_rom_note':'Inherited ROMs copied before build; fingerprint archived after synthesis, with unchanged pre-build modification time',
  'netlist_sha256':sha(net),'netlist_absolute_path':str(net),'synthesis_log_sha256':sha(log),
  'resource_report_sha256':sha(xml),'totals':{k:total(k) for k in ('Register','Lut','Bsram','Ssram','MULT12X12','MULTALU27X18','MULT27X36')},
  'display':[dict(n.attrib) for n in resource.iter() if n.attrib.get('name') in ('display','panel')],
  'hardware_test':'NOT RUN'}
 (V/'synthesis_provenance.json').write_text(json.dumps(proof,indent=2),encoding='utf-8')
 print(json.dumps(proof['totals']))
 return proof
if __name__=='__main__':summarize()
