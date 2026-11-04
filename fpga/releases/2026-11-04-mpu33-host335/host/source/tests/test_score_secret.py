import os,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from lab_secret import save_key,load_key

@unittest.skipUnless(os.name=='nt','Windows DPAPI')
class SecretTests(unittest.TestCase):
    def test_encrypted_roundtrip_delete_and_corruption(self):
        with tempfile.TemporaryDirectory() as folder:
            key='test-only-not-a-real-api-key'
            save_key(folder,key);path=Path(folder)/'ai-key.dpapi'
            self.assertNotIn(key.encode(),path.read_bytes());self.assertEqual(load_key(folder),key)
            path.write_bytes(b'corrupt')
            with self.assertRaises(ValueError):load_key(folder)
            save_key(folder,'');self.assertFalse(path.exists());self.assertEqual(load_key(folder),'')
    def test_ui_save_and_reload(self):
        from PySide6 import QtCore as C,QtWidgets as W
        from tanglab import Window
        import lab_score_import as imp
        app=W.QApplication.instance() or W.QApplication([]);C.QStandardPaths.setTestModeEnabled(True)
        original=imp.data_dir
        with tempfile.TemporaryDirectory() as folder:
            imp.data_dir=lambda:Path(folder)
            w=Window();w.timer.stop()
            try:
                w.score_ai_url.setText('https://example.com/v1');w.score_ai_model.setText('mock')
                w.score_ai_key.setText('mock-persisted-key');w.score_remember_key.setChecked(True);imp.save_settings(w)
                self.assertNotIn('mock-persisted-key',(Path(folder)/'ai-settings.json').read_text())
                other=Window();other.timer.stop()
                try:
                    self.assertEqual(other.score_ai_key.text(),'mock-persisted-key');self.assertTrue(other.score_remember_key.isChecked())
                    other.score_remember_key.setChecked(False);imp.save_settings(other);self.assertEqual(load_key(folder),'')
                finally:other.close()
            finally:w.close();imp.data_dir=original;app.processEvents()

if __name__=='__main__':unittest.main()
