"""Ordinary mouse notes do not require an IMU/virtual-pose lease."""
def prepare(c,j,basic):
    e=c.engine
    if "LITE29" in e.device:return
    if not e.capabilities.get('gesture_v24'):return
    g=e.instrument_state.get('gesture',{})
    if basic:
        if getattr(e,'mouse_wrist_saved',None) is None:
            e.mouse_wrist_saved=dict(enabled=list(g.get('enabled',[True,True])),invert=list(g.get('invert',[False,False])))
        if any(g.get('enabled',[True,True])):
            from lab_gesture import execute
            c.ack(j,e.send(51));c.wait(j,lambda:not e.duo.get('running'),3,'等待停止状态读回超时')
            execute(c,j,'gesture.configure',dict(enabled=[False,False],invert=list(g.get('invert',[False,False]))))
    else:restore(c,j)

def restore(c,j):
    e=c.engine;saved=getattr(e,'mouse_wrist_saved',None)
    if saved is None:return
    from lab_gesture import execute
    c.ack(j,e.send(51));c.wait(j,lambda:not e.duo.get('running'),3,'等待停止状态读回超时')
    execute(c,j,'gesture.configure',saved);e.mouse_wrist_saved=None
