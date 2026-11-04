"""Two-voice/SPI bring-up procedure. Never claims simulation is a board test."""
import json,time
from pathlib import Path
import numpy as np
import lab_protocol as P
from lab_engine import LabEngine

def run_test(c,j,params):
    e=c.engine
    if e.recorder:raise ValueError('已有记录，请先停止；自动测试不会覆盖当前记录')
    simulated=params.get('simulation',False)
    if type(simulated) is not bool:raise ValueError('simulation 必须为 true 或 false')
    if simulated:c.execute(j,'demo',{})
    elif not e.ready or not e.source.startswith('真实 FPGA'):raise ValueError('请先连接真实 FPGA；模拟验证需明确传 simulation:true')
    target=params.get('reports_per_type',1000);timeout=params.get('imu_timeout_s',120)
    if type(target) is not int or not 1<=target<=1000 or not isinstance(timeout,(int,float)) or not 1<=timeout<=120:raise ValueError('报告数 1～1000，IMU 超时 1～120 秒')
    out=c.output_dir(params.get('name'));items=[];own_record=False;last_capture=None;record_path=out/'recording'
    report=dict(title='两声部与 SPI 上板测试',source=e.source,simulated=simulated,started=time.strftime('%Y-%m-%d %H:%M:%S'),
                conditions=dict(clock_hz=e.clock,sample_rate=e.fs,frequencies_hz=[375,750],spi_mode=3,spi_hz=1000000,requested_report_hz=100,
                                target_per_type=target,imu_timeout_s=timeout),items=items,
                limitations='数字抓取不证明耳机已发声；两声部不替代四复音验收；未测完整动作到模拟音频延迟。')
    def item(name,passed,detail='',status=None):
        items.append(dict(name=name,status=status or ('通过' if passed else '失败'),basis='模拟' if simulated else '板卡数据',detail=detail))
        c.update(j,'running',name+'：'+items[-1]['status'])
    try:
        item('握手与能力查询',e.ready and e.capabilities['voices']>=4,dict(device=e.device,capabilities=e.capabilities))
        c.preview(j,False);e.start_record(record_path);own_record=True
        start_errors=e.parser.errors;start_gaps=e.gaps
        for name,active in [('仅声部一',[True,False]),('仅声部二',[False,True]),('双声部',[True,True]),('双路静音',[False,False])]:
            values=[dict(channel=i,hz=[375,750,1125,1500][i],gain=.12,wave=0,gate=active[i] if i<2 else False,
                         attack=10,decay=80,sustain=.7,release=180) for i in range(4)]
            c.voices(j,values);c.delay(j,.4);c.capture(j);a,fs=c.audio();last_capture=a.copy()
            c.write_audio(out/(name+'.csv'),a,fs)
            good=a.shape==(2048,5) and fs==48000;details=dict(shape=list(a.shape),sample_rate=fs,channels=[])
            for k in range(4):
                peak=int(np.abs(a[:,k].astype(np.int32)).max());expected=active[k] if k<2 else False
                if expected:
                    bins=np.abs(np.fft.rfft(a[:,k]*np.hanning(len(a))));frequency=float(np.fft.rfftfreq(len(a),1/fs)[int(np.argmax(bins))])
                    ok=peak>100 and abs(frequency-[375,750][k])<=fs/len(a)
                else:frequency=None;ok=peak<=3
                good=good and ok;details['channels'].append(dict(channel=k,peak_pcm=peak,peak_hz=frequency,passed=ok))
            mix=np.clip(a[:,:4].astype(np.int64).sum(axis=1),-32768,32767)
            error=int(np.max(np.abs(mix-a[:,4])));good=good and error<=3
            details['mix_max_error_pcm']=error
            if all(active):
                mixed=np.abs(np.fft.rfft(a[:,4]*np.hanning(len(a))));peaks=np.argsort(mixed)[-2:];freq=np.fft.rfftfreq(len(a),1/fs)[peaks]
                details['mix_two_largest_peaks_hz']=sorted(map(float,freq));good=good and all(np.min(abs(freq-hz))<=fs/len(a) for hz in (375,750))
                c.export_to(out)
            item(name+'波形与混音',bool(good),details)
        item('完整抓取传输',e.parser.errors==start_errors and e.gaps==start_gaps,
             dict(crc_or_parse_errors=e.parser.errors-start_errors,missing_frames=e.gaps-start_gaps,
                  note='抓取仅在样本块偏移连续且长度完整后完成；不代替外部时钟或模拟音频测量。'))
        if simulated:item('SPI 配置及三类各 1000 报告',False,'没有真实传感器，未伪造配置或报告。',status='未执行')
        else:
            c.execute(j,'imu.mode',dict(mode=2))
            try:
                configured=c.configure(j,{5:100,1:100,2:100});item('SPI 传感器配置应答',True,configured['confirmed'])
                beginning=dict(e.imu.snapshot()['counts']);start=time.monotonic();counts={}
                while True:
                    current=e.imu.snapshot()['counts'];counts={kind:current.get(kind,0)-beginning.get(kind,0) for kind in ('rotation','accel','gyro')}
                    if all(n>=target for n in counts.values()) or time.monotonic()-start>=timeout:break
                    c.delay(j,.1)
                item('SPI 三类报告持续接收',all(n>=target for n in counts.values()),dict(counts=counts,elapsed_s=time.monotonic()-start,target=target))
                report['imu']=c.reports()
            except (TimeoutError,ValueError,RuntimeError) as exc:item('SPI 配置或接收',False,str(exc))
        c.execute(j,'ping',{})
        report['stats']=e.stats()
        recorder=e.recorder;e.stop_record();own_record=False
        item('原始报文记录',not recorder.error and recorder.dropped==0,dict(directory=str(record_path),error=recorder.error,dropped=recorder.dropped))
        # Validate the saved stream through the same replay engine without disconnecting the board.
        replay=LabEngine()
        try:
            replay.replay(record_path)
            c.wait(j,lambda:replay.status=='回放完成' or replay.status.startswith('回放失败'),180,'记录回放超时')
            same=replay.audio is not None and last_capture is not None and np.array_equal(replay.audio,last_capture)
            item('记录回放与最终采样一致',same and replay.parser.errors==0,dict(status=replay.status,crc_errors=replay.parser.errors))
        finally:replay.close()
    except Exception as exc:
        item('自动流程中断',False,str(exc));report['interrupted']=True
    finally:
        if own_record:e.stop_record()
        tickets=[];cleanup_errors=[]
        if e.ready:
            try:
                tickets.append(e.send(P.PREVIEW,b'\x00'))
                for i in range(4):
                    v=dict(e.voices[i]);v['gate']=False;tickets.append(e.set_voice(i,v))
                end=time.monotonic()+3
                while time.monotonic()<end and any(e.command_result(t)['state'] in ('queued','sent') for t in tickets):time.sleep(.03)
                cleanup_errors=[e.command_result(t) for t in tickets if e.command_result(t)['state'] not in ('acknowledged','simulated')]
            except Exception as exc:cleanup_errors.append(str(exc))
        else:cleanup_errors.append('设备已断连，无法确认松键；请用板上复位或断电静音')
        item('结束清理：停止记录、预览、松键',not cleanup_errors,cleanup_errors or '命令已应答；释音按设置逐渐结束')
        item('耳机/音箱实际发声',False,'请按指南人工试听，数字采样不能证明模拟输出。',status='待人工确认')
        item('控制到模拟音频 ≤10 ms',False,'需要外部仪器和明确测点。',status='未执行')
        report['finished']=time.strftime('%Y-%m-%d %H:%M:%S')
        report['verdict']='失败' if any(x['status']=='失败' for x in items) else ('模拟验证完成（非实测）' if simulated else '数字项目通过，人工项目待确认')
        (out/'测试结果.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        lines=[report['title'],report['verdict'],'数据来源：'+report['source'],report['limitations'],'']
        lines += [f"{x['status']} | {x['name']} | {json.dumps(x['detail'],ensure_ascii=False)}" for x in items]
        (out/'测试结果.txt').write_text('\n'.join(lines),encoding='utf-8-sig')
    return dict(directory=str(out),verdict=report['verdict'],simulated=simulated,items=items)
