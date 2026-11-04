import json
import struct
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from engine import Engine,Recorder
from protocol import encode_packet,from_euler

def pose(seq,yaw):
    return encode_packet(3,seq,bytes((8,seq,3,0))+struct.pack('<4h',*(round(x*16384) for x in from_euler(yaw,0,0))))

class EngineTests(unittest.TestCase):
    def test_drift_wrap(self):
        e=Engine(); e.protocol='UART-SHTP'; e.ingest(pose(0,179),1); e.ingest(pose(1,-179),2)
        self.assertAlmostEqual(e.yaw_accum,2,places=2); self.assertEqual(dict(e.gaps),{})
    def test_reset_invalidates_config(self):
        e=Engine(); e.protocol='UART-SHTP'; e.config.confirmed[5]=5000
        e.ingest(pose(0,0),1); e.ingest(encode_packet(1,0,b'\x01'),2)
        self.assertFalse(e.config.confirmed); self.assertFalse(e.latest)
    def test_config_rvc_rejected(self):
        with self.assertRaises(ValueError): Engine().apply_config({1:100})
    def test_record_replay(self):
        # Tests only own temporary files; no application/shared cache changes.
        with tempfile.TemporaryDirectory() as d:
            e=Engine(); e.protocol='UART-SHTP'; e.source='测试'
            e.recorder=Recorder(Path(d)/'capture',{'protocol':'UART-SHTP'})
            for i in range(40): e.ingest(pose(i,i),1_000_000+i*100_000)
            e.stop_recording()
            original=e.latest['game'][1].values
            e.replay(Path(d)/'capture')
            for t in e.threads: t.join(3)
            self.assertEqual(e.counts['game'],40); self.assertEqual(e.latest['game'][1].values,original)
            m=json.loads((Path(d)/'capture'/'metadata.json').read_text(encoding='utf-8'))
            self.assertEqual(m['record_queue_dropped'],0); self.assertTrue(m['writer_finished']); e.disconnect()
    def test_simulated_rates_and_disconnect(self):
        e=Engine(); e.simulate(); time.sleep(.25); e.disconnect()
        self.assertGreater(e.counts['accel'],60); self.assertEqual(e.counts['report_errors'],0)
        self.assertFalse(e.running)
    def test_serial_open_failure(self):
        with patch('serial.Serial',side_effect=OSError('occupied')):
            e=Engine()
            with self.assertRaises(OSError): e.connect('COM999','UART-RVC')
            self.assertFalse(e.running); self.assertIn('连接失败',e.status)

if __name__=='__main__': unittest.main()
