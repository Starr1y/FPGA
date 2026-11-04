from pathlib import Path
import json,traceback
from PySide6 import QtWidgets as W,QtCore as C,QtGui as G

def start(w,app,out):
 out=Path(out);out.mkdir(parents=True,exist_ok=True);checks=[]
 try:
  w.timer.stop();w.pose_timer.stop();w.isActiveWindow=lambda:True
  w.engine.ready=True;w.engine.device='DUO04 KEY30 LITE29 L331';w.engine.source='模拟检查';w.engine.instrument_state={'mode':1};w.engine.duo['running']=True;w.engine.duo_config['profiles']=[0,0]
  w.keyboard_enabled.setChecked(True);calls=[];w.submit_command=lambda a,p=None:calls.append((a,p)) or {'id':str(len(calls))}
  def key(ch,down=True,pad=False,repeat=False,ctrl=False):
   modifiers=C.Qt.KeyboardModifier.KeypadModifier if pad else C.Qt.KeyboardModifier.NoModifier
   if ctrl:modifiers|=C.Qt.KeyboardModifier.ControlModifier
   return w.eventFilter(w,G.QKeyEvent(C.QEvent.Type.KeyPress if down else C.QEvent.Type.KeyRelease,ord(ch),modifiers,ch,repeat))
  def tap(ch,pad=False):key(ch,pad=pad);key(ch,False,pad)
  w.select_duo(0,3);w.select_duo(1,5);w.select_duo(0,None);assert w.mouse_zones==[3,5]
  calls.clear()
  for ch in 'WSOL':tap(ch)
  assert [(p['hand'],p['velocity'],p['zone']) for a,p in calls if a=='keys33.strike']==[(0,48,3),(0,48,3),(1,48,5),(1,48,5)]
  checks.append('鼠标模式W/S、O/L全部轻音及双手保留选区')
  w.input_mode.setCurrentIndex(1);calls.clear();assert w.pitch_values==[15.,15.]
  key('1');key('1',pad=True);key('1',False);assert (ord('1'),True) in w.keyboard_down;key('1',False,True)
  for n in '234567':tap(n);tap(n,True)
  hits=[p for a,p in calls if a=='keys33.strike'];assert len(hits)==14
  assert sorted((p['hand'],p['zone']) for p in hits)==[(h,z) for h in range(2) for z in range(7)]
  assert all(p['velocity']==48 and p['pitch']==15 for p in hits)
  checks.append('主键盘与小键盘同数字分手；1～7七音映射、默认C4')
  calls.clear();key('2');key('2',repeat=True);key('2',False,repeat=True);assert (ord('2'),False) in w.keyboard_down;key('2',False)
  assert len([1 for a,p in calls if a=='keys33.strike'])==1;checks.append('按住不连发及自动重复释放不误松键')
  tap('W');assert w.pitch_values[1]==40;tap('W');assert w.pitch_values[1]==40
  tap('S');assert w.pitch_values[1]==15;tap('S');assert w.pitch_values[1]==-15;tap('S');assert w.pitch_values[1]==-15
  assert w.pitch_values[0]==15;assert len([1 for a,p in calls if a=='keys33.strike'])==1
  checks.append('W/S仅升降右手C3/C4/C5，边界限幅且不发音')
  w.engine.duo_config['chord']=True;w.update_keyboard_hint();assert not w.octave_boxes[0].isEnabled() and not w.pitch_sliders[0].isEnabled()
  w.octave_boxes[1].setCurrentIndex(1);tap('1');tap('1',True)
  checks.append('左手和弦锁C4、右手中音旋律')
  before=len(calls);key('3',ctrl=True);assert len(calls)==before
  edit=W.QLineEdit(w);original=W.QApplication.focusWidget;W.QApplication.focusWidget=staticmethod(lambda:edit)
  try:tap('3',True);assert len(calls)==before
  finally:W.QApplication.focusWidget=original
  w.engine.duo_config['profiles']=[1,0];tap('3');assert '七音' in w.engine.status;w.engine.duo_config['profiles']=[0,0]
  checks.append('编辑焦点/组合键保护，非七音布局明确拒绝')
  key('A');key('K');assert w.key_masks==[2,2];w.input_mode.setCurrentIndex(0);assert w.key_masks==[0,0] and not w.keyboard_down
  key('A');w.tabs.setCurrentIndex(1);assert w.key_masks==[0,0];w.tabs.setCurrentIndex(0)
  key('K');w.isActiveWindow=lambda:False;w.changeEvent(C.QEvent(C.QEvent.Type.ActivationChange));assert w.key_masks==[0,0] and calls[-1][0]=='duo.stop'
  checks.append('两种模式切换、切页、失焦释放及停止')
  w.isActiveWindow=lambda:True;w.input_mode.setCurrentIndex(1);w.update_keyboard_hint();w.resize(1300,1020);app.processEvents();w.grab().save(str(out/'双模式演奏页.png'))
  w.tabs.setCurrentIndex(3);w.engine.instrument_state={'mode':2,'lesson_source':1,'feedback':0};w.engine.duo['running']=True
  w.engine.score_state.update(loaded=True,selected=True,finished=False,profile=0,position=2,crc32=123,feedback=0,correct=0,wrong=0)
  w.controller.job=lambda jid:{'state':'completed'};w.score_fans[0].setFocusPolicy(C.Qt.FocusPolicy.StrongFocus);w.score_fans[0].setFocus();app.processEvents();calls.clear()
  for n in '1234567':tap(n);tap(n,True)
  answers=[p for a,p in calls if a=='lesson.key'];assert len(answers)==14 and sorted((p['hand'],p['zone']) for p in answers)==[(h,z) for h in range(2) for z in range(7)]
  assert all(p['position']==2 and p['crc32']==123 for p in answers)
  checks.append('教学页双手七音数字映射及目标快照；错手也交给板上判题')
  before=len(calls);key('1');key('1',repeat=True);key('1',False,repeat=True);key('1',False);assert len(calls)==before+1
  w.engine.score_state['feedback']=1;before=len(calls);tap('2');assert len(calls)==before;w.engine.score_state['feedback']=0
  w.engine.duo['running']=False;tap('2');assert len(calls)==before;w.engine.duo['running']=True
  w.engine.instrument_state['lesson_source']=0;tap('2');assert len(calls)==before;w.engine.instrument_state['lesson_source']=1
  w.controller.job=lambda jid:{'state':'running'};tap('2');assert len(calls)==before;w.controller.job=lambda jid:{'state':'completed'}
  checks.append('教学按住不连发、反馈不缓存、暂停/真实来源/在途判题禁止新事件')
  old_focus=W.QApplication.focusWidget;W.QApplication.focusWidget=staticmethod(lambda:edit)
  try:tap('2');assert len(calls)==before
  finally:W.QApplication.focusWidget=old_focus
  key('3',ctrl=True);assert len(calls)==before
  checks.append('教学编辑焦点与Ctrl保护')
  w.score_source.setCurrentIndex(1);w.score_target.setText('离线检查：右手DO · 数字小键盘1作答（非板卡实测）');app.processEvents();scroll=w.tabs.widget(3).findChild(W.QScrollArea);scroll.verticalScrollBar().setValue(scroll.verticalScrollBar().maximum());app.processEvents();w.grab().save(str(out/'教学数字映射页.png'))
  (out/'result.json').write_text(json.dumps({'result':'PASS','checks':checks,'hardware':'not tested'},ensure_ascii=False,indent=2),encoding='utf8')
 finally:
  w.engine.ready=False;w.controller.closed.set();w.close()

