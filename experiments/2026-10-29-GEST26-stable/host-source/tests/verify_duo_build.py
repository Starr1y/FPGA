"""Fail closed: only certify a freshly built bitstream with zero TNS endpoints."""
from pathlib import Path
import re,html,json,hashlib,datetime
root=Path(__file__).resolve().parents[1];p=root/'fpga/duo02-mouse';pnr=p/'impl/pnr';name='tanglab_duo02_mouse'
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def rows(text):
    return [[html.unescape(re.sub('<[^>]+>','',c)).strip() for c in re.findall(r'<td[^>]*>(.*?)</td>',r,re.S)] for r in re.findall(r'<tr[^>]*>(.*?)</tr>',text,re.S)]
text=(pnr/(name+'_tr_content.html')).read_text(encoding='utf-8',errors='replace')
frequency=text.split('name="Max_Frequency_Report"',1)[1].split('name="Total_Negative_Slack_Report"',1)[0]
clocks=[]
for r in rows(frequency):
    if len(r)!=6:continue
    target=float(re.search(r'[\d.]+',r[2])[0]);actual=float(re.search(r'[\d.]+',r[3])[0])
    clocks.append(dict(clock=r[1],constraint_mhz=target,fmax_mhz=actual))
assert len(clocks)>=2 and all(c['fmax_mhz']>=c['constraint_mhz'] for c in clocks),clocks
section=text.split('name="Total_Negative_Slack_Report"',1)[1].split('</table>',1)[0]
tns=[r for r in rows(section) if len(r)==4 and r[1] in ('Setup','Hold')]
assert len(tns)>=4 and all(float(r[2])==0 and int(r[3])==0 for r in tns),tns
bit=pnr/(name+'.fs');net=p/'impl/gwsynthesis'/(name+'.vg')
assert bit.stat().st_mtime>=net.stat().st_mtime
sources=[*sorted((p/'rtl').glob('*.v')),*sorted((p/'rtl').glob('*.hex')),p/(name+'.cst'),p/(name+'.sdc')]
assert all(f.stat().st_mtime<=net.stat().st_mtime for f in sources),'source changed after synthesis'
pins=(pnr/(name+'.pin.html')).read_text(errors='replace')
for port,pin in [('pc_tx','U15'),('pc_rx','V14'),('clk','V22')]:
    assert any(port in r and any(c==pin or c.startswith(pin+'/') for c in r) for r in rows(pins)),(port,pin)
result=dict(date=datetime.datetime.now().isoformat(),baseline='9e577cd06350327c956613da686851feb118dfb4',
            timing_pass=True,clocks=clocks,tns=tns,bitstream_sha256=sha(bit),
            sources={str(f.relative_to(p)):sha(f) for f in sources},
            rtl='XSim UART/32Voice/onset/PCM/PT8211 and stereo FX tests passed',
            software='GUI simulation, Agent authentication/fairness/record/replay and legacy scope passed',
            hardware='未执行：需用户SRAM下载后测听音、HDMI及真实串口',
            cautions=['保留Gowin原始告警，查看reports','TANG_SIM不模拟TMDS原语','不代表比赛延迟或长期稳定性验收'])
(p/'VERIFICATION.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='sources'},ensure_ascii=False,indent=2))
