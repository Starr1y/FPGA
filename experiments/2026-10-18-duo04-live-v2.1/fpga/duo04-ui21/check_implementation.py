"""Read-only evidence check after USER runs Gowin. Never starts EDA tools."""
from pathlib import Path
import re,json,hashlib,sys,html
root=Path(__file__).resolve().parent;pnr=root/'impl/pnr'
def clean(s):return html.unescape(re.sub('<[^>]*>',' ',s))
log=pnr/'tanglab_duo04.log';bit=pnr/'tanglab_duo04.fs'
result={'project':'DUO04-LIVE 2.1','synthesis_or_pnr_started_by_checker':False,'board_test':'NOT RUN'}
if not log.exists():
    result.update(status='NOT RUN',reason='尚无本工程布局布线日志；请在IDE自行执行')
else:
    text=log.read_text(errors='replace');errors=re.findall(r'^.*(?:ERROR|PR1014).*$',text,re.M)
    result.update(bitstream_generated='Bitstream generation completed' in text and bit.exists(),errors_or_clock_warnings=errors)
    timing=pnr/'tanglab_duo04_tr_content.html'
    if timing.exists():
        raw=timing.read_text(errors='replace');tables=[]
        section=raw.split('Total Negative Slack Summary:',1)[-1].split('Timing Details',1)[0]
        for row in re.findall(r'<tr[^>]*>(.*?)</tr>',section,re.S):
            cells=[clean(c).strip() for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S)]
            if cells:tables.append(cells)
        result['negative_slack_rows']=tables
        nonzero=[r for r in tables if len(r)>=4 and r[1] in ('Setup','Hold') and (float(r[2])!=0 or int(r[3])!=0)]
        result['reported_tns_zero']=not nonzero and any(len(r)>=4 and r[1]=='Setup' for r in tables)
    result['status']='REVIEW REQUIRED'
    if result.get('bitstream_generated') and not errors and result.get('reported_tns_zero'):
        result['status']='REPORTED PATHS PASS; manually check clock routes and unconstrained paths'
    if bit.exists():result['bitstream_sha256']=hashlib.sha256(bit.read_bytes()).hexdigest()
print(json.dumps(result,ensure_ascii=False,indent=2))
sys.exit(2 if result['status']=='NOT RUN' else 1 if result.get('errors_or_clock_warnings') or not result.get('reported_tns_zero') else 0)
