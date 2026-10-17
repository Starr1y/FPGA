"""Repeated true gate edges through the GUI API; no flashing, ends muted."""
import argparse,json,time,urllib.request
from pathlib import Path
import numpy as np

def main():
    p=argparse.ArgumentParser();p.add_argument('--session',required=True);p.add_argument('--out',required=True)
    a=p.parse_args();s=json.loads(Path(a.session).read_text(encoding='utf-8'))
    if not s['url'].startswith('http://127.0.0.1:'):raise ValueError('Loopback required')
    def api(path,body=None):
        r=urllib.request.Request(s['url']+'/api/v1/'+path,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization':'Bearer '+s['token'],'Content-Type':'application/json'})
        with urllib.request.urlopen(r,timeout=8) as f:return json.load(f)
    def run(action,params=None):
        j=api('commands',dict(action=action,params=params or {}));end=time.monotonic()+20
        while j['state'] not in ('completed','failed','cancelled'):
            if time.monotonic()>end:raise TimeoutError(action)
            time.sleep(.015);j=api('jobs/'+j['id'])
        if j['state']!='completed':raise RuntimeError(j['message'])
        return j
    before=api('status');time.sleep(.5);now=api('status')
    if before['capture_revision']!=now['capture_revision'] or now['active_job']:
        raise RuntimeError('请先停止连续抓取并等待队列空闲')
    if not now['ready'] or not now['source'].startswith('真实 FPGA') or not now['capabilities'].get('piano_control'):
        raise RuntimeError('Real connected piano-control firmware required')
    out=Path(a.out);out.mkdir(parents=True,exist_ok=False)
    report=dict(source=now['source'],device=now['device'],simulated=False,tests=[],started=time.strftime('%Y-%m-%d %H:%M:%S'))
    values=[dict(channel=i,hz=375*(i+1),gain=.002,wave=4 if i==0 else 0,
        gate=False,attack=10,decay=80,sustain=.7,release=180,piano_hold=False,piano_decay_s=6) for i in range(4)]
    try:
        run('preview',dict(enabled=False))
        for index in range(10):
            values[0]['gate']=False;off=run('voices.set',dict(voices=values))
            # Let audio sampling observe the off edge, then submit a fresh on edge.
            time.sleep(.025 if index%2 else .2)
            values[0]['gate']=True;on=run('voices.set',dict(voices=values))
            captured=run('capture',dict(points=512,trigger=0));data=api('capture')
            if data['revision']!=captured['result']['revision']:raise RuntimeError('Concurrent capture detected')
            samples=np.asarray(data['samples'],dtype=np.int16)
            peak=int(np.max(np.abs(samples[:,0].astype(int))));rms=float(np.sqrt(np.mean(samples[:,0].astype(float)**2)))
            good=peak>=10 and not np.any(samples[:,1:4]) and np.array_equal(samples[:,0],samples[:,4])
            np.savetxt(out/f'note-{index+1:02d}.csv',samples,delimiter=',',fmt='%d',header='voice1,voice2,voice3,voice4,mix',comments='')
            report['tests'].append(dict(index=index+1,passed=good,peak_pcm=peak,rms_pcm=rms,
                off_job=off['id'],on_job=on['id'],capture_job=captured['id'],on_ack_history=on['history']))
            print(f"{'PASS' if good else 'FAIL'} note {index+1}/10 peak={peak} RMS={rms:.3f}",flush=True)
    except Exception as exc:report['error']=str(exc)
    finally:
        try:run('voices.release');report['cleanup_muted']=True
        except Exception as exc:report['cleanup_muted']=False;report['cleanup_error']=str(exc)
        final=api('status');report['crc_delta']=final['stats']['crc_errors']-now['stats']['crc_errors']
        report['missing_delta']=final['stats']['missing_frames']-now['stats']['missing_frames']
        report['passed']=len(report['tests'])==10 and all(x['passed'] for x in report['tests']) and not report.get('error') and report['cleanup_muted'] and report['crc_delta']==0 and report['missing_delta']==0
        (out/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print('Final:',report['passed'],'CRC +',report['crc_delta'],'missing +',report['missing_delta'],flush=True)
    return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
