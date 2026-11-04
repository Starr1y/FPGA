"""Shared command dispatcher for score uploads; board owns practice judging."""
import struct,time,secrets,zlib
from lab_score import compile_score

def apply_state(e):
    q=e.score_state;s=e.instrument_state
    if s.get('mode')==2 and s.get('lesson')==3 and q.get('selected'):
        s.update(position=q['position'],target_hand=q['hand'],target_note=q['note'],target_zone=q['zone'],finished=q['finished'],feedback=q['feedback'],correct=q['correct'],wrong=q['wrong'],lesson_total=q['total'])

def frame(e,f):
    if f.kind!=141:return False
    b=f.payload
    if len(b)!=48 or b[0]!=1:raise ValueError('曲目状态报文格式错误')
    u=lambda n:struct.unpack_from('<I',b,n)[0]
    h=lambda n:struct.unpack_from('<H',b,n)[0]
    e.score_state=dict(loaded=bool(b[1]),uploading=bool(b[2]),busy=bool(b[3]),crc32=u(4),total=h(8),position=h(10),profile=b[12],hand=b[13],note=b[14],zone=b[15],octave=b[16],feedback=b[17],finished=bool(b[18]),target_ready=bool(b[19]),transfer_id=u(20),uploaded=h(24),last_code=b[26],selected=bool(b[27]),revision=h(28),readback_index=h(30),readback_word=u(32),readback_revision=h(36),hold_ms=h(38),correct=h(40),wrong=h(42))
    e.score_revision+=1;apply_state(e);return True

def execute(c,j,action,p):
    e=c.engine
    if action=='score.validate':
        out=compile_score(p.get('score',p.get('path')),p.get('layout','auto'))
        return {k:v for k,v in out.items() if k not in ('words',)}
    if not e.ready:raise ValueError('请先连接FPGA或开启四音色模拟')
    if not e.capabilities.get('score_v1'):raise ValueError('需要重新编译烧录GEST27曲谱固件，旧固件不支持上传')
    if action=='score.status':
        before=e.score_revision;c.ack(j,e.send(74));c.wait(j,lambda:e.score_revision>before,3,'曲目状态读回超时')
        return dict(source=e.source,score=dict(e.score_state))
    if action!='score.upload':raise ValueError('未知曲谱操作')
    out=compile_score(p.get('score',p.get('path')),p.get('layout','auto'))
    if out['requires_confirmation'] and p.get('confirmed') is not True:raise ValueError('曲谱需要八度/时值适配；先查看score.validate结果并确认')
    e.score_upload_epoch+=1
    c.ack(j,e.send(51))
    # Capture jobs already on wire may finish, but no new automatic capture is admitted.
    c.wait(j,lambda:not any(x['action']=='capture' and x['state'] in ('queued','running','acknowledged') for x in c.jobs.values()),20,'等待在途采样结束超时')
    transfer=secrets.randbits(32);success=False
    try:
        c.ack(j,e.send(69,struct.pack('<IBHI',transfer,out['profile'],out['count'],out['crc32'])))
        for offset in range(0,out['count'],12):
            words=out['words'][offset:offset+12]
            before=e.score_revision
            c.ack(j,e.send(70,struct.pack('<IHB',transfer,offset,len(words))+struct.pack('<'+'I'*len(words),*words)))
            c.wait(j,lambda:e.score_revision>before and e.score_state.get('transfer_id')==transfer and e.score_state.get('uploaded')==offset+len(words),3,'数据块已应答但进度未确认')
            c.update(j,'running',f'已确认上传 {offset+len(words)}/{out["count"]} 步',progress=(offset+len(words))/out['count'])
        before=e.score_revision;c.ack(j,e.send(71,struct.pack('<I',transfer)))
        c.wait(j,lambda:e.score_revision>before and e.score_state.get('loaded') and e.score_state.get('crc32')==out['crc32'] and e.score_state.get('total')==out['count'] and not e.score_state.get('uploading'),3,'曲目提交后的CRC/数量读回失败')
        # Full readback verifies actual active RAM, not merely a cached ACK.
        for i,word in enumerate(out['words']):
            before=e.score_state.get('readback_revision',0)
            c.ack(j,e.send(73,struct.pack('<H',i)))
            c.wait(j,lambda:e.score_state.get('readback_revision')!=before and e.score_state.get('readback_index')==i,3,'曲目读回超时')
            if e.score_state['readback_word']!=word:raise ValueError(f'第{i+1}步RAM读回不一致')
            if i%32==0:c.update(j,'running',f'完整校验读回 {i+1}/{out["count"]} 步',progress=1,verification=(i+1)/out['count'])
        success=True
        return dict(accepted=True,verified=True,title=out['score']['title'],steps=out['count'],crc32=out['crc32'],profile=out['profile'],volatile=True,source=e.source,started=False)
    finally:
        if not success:
            # Cancellation cannot wait on the cancelled job. Preserve active bank and queue abort.
            try:e.send(72)
            except Exception:pass

def simulate(e,kind,b):
    q=e.score_sim;s=e.score_state
    if kind==69:
        tid,profile,total,crc=struct.unpack('<IBHI',b)
        if q.get('id')!=tid:q.update(id=tid,profile=profile,total=total,expected=crc,staging=[])
        s.update(uploading=True,transfer_id=tid,uploaded=len(q['staging']))
    elif kind==70:
        tid,offset,count=struct.unpack_from('<IHB',b);words=list(struct.unpack_from('<'+'I'*count,b,7))
        if tid!=q.get('id') or offset>len(q['staging']):raise ValueError('模拟：上传偏移错误')
        if offset<len(q['staging']):
            if q['staging'][offset:offset+count]!=words:raise ValueError('模拟：重复块不一致')
        else:q['staging']+=words
        s['uploaded']=len(q['staging'])
    elif kind==71:
        data=struct.pack('<'+'I'*len(q['staging']),*q['staging'])
        if len(q['staging'])!=q['total'] or zlib.crc32(data)&0xffffffff!=q['expected']:raise ValueError('模拟：曲目CRC错误')
        q['active']=list(q['staging']);s.update(loaded=True,uploading=False,total=q['total'],crc32=q['expected'],profile=q['profile'],revision=s.get('revision',0)+1)
    elif kind==72:s['uploading']=False
    elif kind==73:
        i=struct.unpack('<H',b)[0]
        if i>=len(q.get('active',[])):raise ValueError('模拟：无该步骤')
        s.update(readback_index=i,readback_word=q['active'][i],readback_revision=s.get('readback_revision',0)+1)
    s['last_code']=0;e.score_revision+=1

def simulation_target(e):
    s=e.instrument_state;q=e.score_state
    if s.get('lesson')!=3:return False
    i=s.get('position',0);words=e.score_sim.get('active',[]);finished=i>=len(words)
    word=words[min(i,len(words)-1)] if words else (500<<16)|(60<<9)
    n=(word>>9)&127;hand=(word>>8)&1;zone=(word>>4)&15;octave=(word>>2)&3
    q.update(position=i,hand=hand,note=n,zone=zone,octave=octave,feedback=s.get('feedback',0),finished=finished,target_ready=not finished,selected=s.get('mode')==2,hold_ms=word>>16,correct=s.get('correct',0),wrong=s.get('wrong',0))
    s.update(target_hand=hand,target_note=n,target_zone=zone,finished=finished,lesson_total=len(words),octave_codes=[octave,octave])
    e.duo_config.update(profiles=[q.get('profile',0)]*2,chord=False)
    return True
