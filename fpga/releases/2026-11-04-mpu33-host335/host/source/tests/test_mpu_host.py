import os,sys,struct,unittest
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6 import QtWidgets as W,QtCore as C
from lab_engine import LabEngine
import lab_protocol as P
class MPUHostTests(unittest.TestCase):
 def test_identity_and_diagnostic_ui(self):
  app=W.QApplication.instance() or W.QApplication([]);C.QStandardPaths.setTestModeEnabled(True)
  from tanglab import Window
  import lab_diagnostic as D
  w=Window();w.timer.stop()
  try:
   e=w.engine
   e.ingest(P.pack(P.INFO,struct.pack('<HIIBH',1,50000000,48000,32,2048)+b'DUO04-LIVE 2.1+GEST27+MPU6050',1))
   self.assertTrue(e.ready);self.assertTrue(e.capabilities['mpu6050']);self.assertTrue(e.capabilities['score_v1']);self.assertFalse(w.tabs.isTabEnabled(2))
   b=bytearray(192)
   for h in range(2):struct.pack_into('<I',b,h*96,0x29b|(50<<12));b[h*96+74]=2
   e.instrument_state['diagnostic']=D.decode(b);e.duo_revision+=1;D.refresh(w)
   self.assertIn('本地滤波已就绪',w.diag_cards[0].text());self.assertIn('MPU6050',w.diag_cards[1].text())
  finally:w.close();app.processEvents()
if __name__=='__main__':unittest.main(verbosity=2)
