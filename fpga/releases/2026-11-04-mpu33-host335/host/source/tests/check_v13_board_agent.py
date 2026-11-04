"""Explicit real-board smoke test through the running GUI's authenticated API.

No flashing, no IMU configuration, no second serial owner. Ends with all gates off.
"""
import argparse,json,time,statistics,urllib.request
from pathlib import Path
import numpy as np

def main():
    p=argparse.ArgumentParser();p.add_argument('--session',required=True);p.add_argument('--out',required=True)
    args=p.parse_args();session=json.loads(Path(args.session).read_text(encoding='utf-8'))
    if not session['url'].startswith('http://127.0.0.1:'):raise ValueError('Only loopback is supported')
    def api(path,body=None):
        data=None if body is None else json.dumps(body).encode('utf-8')
        request=urllib.request.Request(session['url']+'/api/v1/'+path,data=data,
            headers={'Authorization':'Bearer '+session['token'],'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=8) as response:return json.load(response)
    def run(action,params=None,timeout=25):
        job=api('commands',dict(action=action,params=params or {}));end=time.monotonic()+timeout
        while job['state'] not in ('completed','failed','cancelled'):
            if time.monotonic()>end:raise TimeoutError(action+' API task timeout: '+job['id'])
            time.sleep(.03);job=api('jobs/'+job['id'])
        if job['state']!='completed':raise RuntimeError(action+': '+job['message'])
        return job['result']
    status=api('status')
    if not status['ready'] or status['device'] not in ('TangLab 1.3','TangLab 1.3.1') or not status['source'].startswith('真实 FPGA'):
        raise RuntimeError('Please connect the real TangLab 1.3 FPGA in the GUI first')
    out=Path(args.out);out.mkdir(parents=True,exist_ok=False)
    report=dict(source=status['source'],device=status['device'],baud=status['baud'],
                simulated=False,started=time.strftime('%Y-%m-%d %H:%M:%S'),tests=[],
                note='真实板卡数字采样检查；不证明实际听音、模拟延迟或IMU功能。')
    def check(name,passed,**details):
        report['tests'].append(dict(name=name,passed=bool(passed),**details))
        print(('PASS ' if passed else 'FAIL ')+name,flush=True)
    def capture(points,name):
        result=run('capture',dict(points=points,trigger=0))
        data=api('capture');a=np.asarray(data['samples'],dtype=np.int16)
        if data['revision']!=result['revision']:raise RuntimeError('GUI has another capture running; please stop automatic capture')
        assert a.shape==(points,5) and data['sample_rate']==48000
        np.savetxt(out/(name+'.csv'),np.column_stack((np.arange(points)/48000,a)),delimiter=',',
                   header='time_s,voice1,voice2,voice3,voice4,mix',comments='',encoding='utf-8-sig')
        return a,result
    recording=False
    try:
        run('preview',dict(enabled=False))
        tag='v13-hardware-'+time.strftime('%Y%m%d-%H%M%S')
        report['recording']=run('record.start',dict(name=tag));recording=True
        values=[dict(channel=i,hz=375*(i+1),gain=.002,wave=0,gate=i<2,
                     attack=10,decay=80,sustain=.7,release=180,piano_hold=False,piano_decay_s=6)
                for i in range(4)]
        run('voices.set',dict(voices=values));time.sleep(.25)
        for points in (512,2048):
            before=api('status')['stats'];timings=[];received=[];details=[]
            for index in range(10):
                a,r=capture(points,f'{points}-{index+1:02d}')
                f=np.fft.rfftfreq(points,1/48000)
                peaks=[float(f[np.argmax(np.abs(np.fft.rfft(a[:,i]*np.hanning(points))))]) for i in range(2)]
                mix_error=int(np.abs(a[:,:4].astype(np.int64).sum(axis=1)-a[:,4]).max())
                good=all(abs(x-y)<=48000/points for x,y in zip(peaks,(375,750))) and mix_error==0 and not np.any(a[:,2:4])
                details.append(dict(index=index+1,peaks_hz=peaks,mix_error_pcm=mix_error,passed=good,timing=r['timing']))
                timings.append(r['timing']['receive_ms']);received.append(r['timing']['received_at'])
                print(f'{points}: {index+1}/10, receive {timings[-1]:.1f} ms',flush=True)
            after=api('status')['stats'];crc=after['crc_errors']-before['crc_errors'];missing=after['missing_frames']-before['missing_frames']
            intervals=np.diff(received)
            check(f'{points} points / ten captures',all(x['passed'] for x in details) and crc==0 and missing==0,
                  completed=len(details),crc_delta=crc,missing_delta=missing,details=details,
                  receive_ms=dict(min=min(timings),median=statistics.median(timings),p95=float(np.percentile(timings,95)),max=max(timings)),
                  interval_s=dict(median=float(np.median(intervals)),min=float(intervals.min()),max=float(intervals.max())))
        report['export']=run('export',dict(name=tag+'-export'))
        # A true gate transition, followed by more than ten seconds of sustain.
        run('voices.release');time.sleep(.25)
        run('voices.set',dict(voices=[dict(channel=0,wave=4,gate=True,piano_hold=True,piano_decay_s=6)]))
        began=time.monotonic();time.sleep(.25)
        a,_=capture(512,'piano-hold-start');early=float(np.sqrt(np.mean(a[:,0].astype(float)**2)))
        while time.monotonic()-began<11:time.sleep(.1)
        a,_=capture(512,'piano-hold-after-11s');late=float(np.sqrt(np.mean(a[:,0].astype(float)**2)))
        check('piano hold over eleven seconds',early>0 and late>early*.5,early_rms_pcm=early,late_rms_pcm=late,elapsed_s=time.monotonic()-began)
        run('voices.set',dict(voices=[dict(channel=0,piano_hold=False,piano_decay_s=6)]))
        began=time.monotonic();a,_=capture(512,'piano-decay-start');t0=time.monotonic()-began
        start_rms=float(np.sqrt(np.mean(a[:,0].astype(float)**2)))
        while time.monotonic()-began<6:time.sleep(.05)
        a,_=capture(512,'piano-decay-after-6s');end_rms=float(np.sqrt(np.mean(a[:,0].astype(float)**2)))
        check('piano decays after hold disabled',start_rms>0 and 0<end_rms<start_rms*.25,
              start_rms_pcm=start_rms,end_rms_pcm=end_rms,ratio=end_rms/start_rms if start_rms else None,
              elapsed_s=time.monotonic()-began,note='低增益PCM量化与电脑调度下的近似功能检查，不是精确T10测量。')
        run('voices.release');time.sleep(.3)
        a,_=capture(512,'released-silence');check('all voices release to silence',not np.any(a))
    except Exception as exc:
        check('test interrupted',False,error=str(exc));report['error']=str(exc)
    finally:
        cleanup=[]
        for action,params in [('preview',dict(enabled=False)),('voices.release',{}),('record.stop',{})]:
            try:run(action,params)
            except Exception as exc:cleanup.append(action+': '+str(exc))
        check('cleanup record/preview/voices',not cleanup,errors=cleanup)
        report['finished']=time.strftime('%Y-%m-%d %H:%M:%S');report['passed']=all(t['passed'] for t in report['tests'])
        report['final_stats']=api('status')['stats']
        (out/'硬件测试结果.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        lines=['TangLab 1.3 实物音频检查',report['source'],report['note']]+[
            ('通过' if t['passed'] else '失败')+' | '+t['name'] for t in report['tests']]
        (out/'硬件测试结果.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
