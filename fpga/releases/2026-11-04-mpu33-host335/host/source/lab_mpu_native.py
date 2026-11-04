"""Versioned native MPU diagnostics. Explicit identity compatibility."""
import struct,time
ERRORS={0:'正常',1:'I²C无应答',2:'事务异常',3:'配置读回失败',4:'数据就绪标记异常',5:'报告中断',6:'样本过期',7:'身份异常',13:'SCL拉伸超时',14:'总线未释放',15:'事务状态异常'}
def decode(b):
    if len(b)!=52 or b[0]!=1 or b[1]!=2:raise ValueError('不支持的MPU诊断格式')
    hands=[]
    for h in range(2):
        p=b[4+h*24:28+h*24];flags=p[3]
        hands.append(dict(who=p[0],error=p[1],zero_check_failed=bool(flags&1),configured=bool(flags&2),online=bool(flags&4),orientation_ready=bool(flags&8),calibrated=bool(flags&16),calibrating=bool(flags&32),identity_compat=bool(flags&64),int_level=bool(flags&128),samples=struct.unpack_from('<I',p,4)[0],errors=struct.unpack_from('<I',p,8)[0],age_ms=struct.unpack_from('<I',p,12)[0]/10,interrupts=struct.unpack_from('<I',p,16)[0],state=p[20],register=p[21],read=p[22]))
    return dict(version=1,allow_identity75=b[2]&3,hands=hands)
def describe(m,connected,supported):
    if not connected:return '手柄状态：请先连接设备'
    if not supported:return '当前固件未提供原生MPU诊断'
    if not m:return '正在等待手柄状态'
    if time.monotonic()-m.get('received_at',0)>1:return '手柄诊断已过期，请刷新连接状态'
    lines=[]
    for h,p in enumerate(m['hands']):
        if p.get('zero_check_failed'):state='归中零点校验失败，请保持中立后重新归中'
        elif p['who']==0x75:
            phase=(ERRORS.get(p['error'],'采集异常') if p['error'] else '初始化中') if not p['online'] else '归中中' if p['calibrating'] else '已归中' if p['calibrated'] else '静止准备中' if not p['orientation_ready'] else '在线，等待归中'
            state='身份异常兼容模式 · '+phase if p['identity_compat'] else '身份异常0x75，兼容读取尚未开启'
        elif not p['online']:
            state='未收到INT' if p['error']==5 and p['interrupts']==0 else ERRORS.get(p['error'],'采集异常') if p['error'] else '初始化中'
        else:state='归中中' if p['calibrating'] else '已归中' if p['calibrated'] else '静止准备中' if not p['orientation_ready'] else '在线，等待归中'
        lines.append(f"{'左' if h==0 else '右'}手：{state} · 身份0x{p['who']:02X} · INT {p['interrupts']} · 样本 {p['samples']} · 年龄 {p['age_ms']:.1f}ms · {ERRORS.get(p['error'],'未知错误')}")
    return '\n'.join(lines)
