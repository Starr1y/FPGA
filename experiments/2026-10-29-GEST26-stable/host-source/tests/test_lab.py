import unittest,struct,tempfile,time
from pathlib import Path
import numpy as np
import lab_protocol as P
from lab_engine import LabEngine

class WireTests(unittest.TestCase):
    def test_crc_standard(self):self.assertEqual(P.crc16(b'123456789'),0x29b1)
    def test_fragment_noise_and_corruption(self):
        good=P.pack(P.ACK,b'\x01\x00\x00',9,17);bad=bytearray(good);bad[-1]^=1
        parser=P.Parser();out=[]
        for b in b'noise'+bad+good:out+=parser.feed(bytes([b]))
        self.assertEqual(len(out),1);self.assertEqual(out[0].seq,9);self.assertEqual(out[0].tick,17);self.assertEqual(parser.errors,1)
    def test_timeout_and_oversize(self):
        p=P.Parser();p.feed(b'\xa5\x5a\x01',1);out=p.feed(P.pack(P.PONG,b''),3)
        self.assertEqual(len(out),1);self.assertEqual(p.errors,1)
        p.feed(b'\xa5\x5a'+struct.pack('<BBHHI',1,1,6000,0,0));self.assertGreater(p.errors,1)
    def test_capture_continuity(self):
        e=LabEngine();a=np.arange(320,dtype=np.int16).reshape(64,5)
        def block(off):return P.pack(P.AUDIO,struct.pack('<HHHI',7,off,64,48000)+a[off:off+32].astype('<i2').tobytes(),off//32)
        e.ingest(block(32));self.assertIsNone(e.audio);e.ingest(block(0));np.testing.assert_array_equal(a,e.audio);e.close()
    def test_bad_capture(self):
        e=LabEngine();e.ingest(P.pack(P.AUDIO,struct.pack('<HHHI',1,30,32,48000)+bytes(40)))
        self.assertEqual(e.parser.errors,1);self.assertIsNone(e.audio);e.close()
    def test_imu_timestamp_wrap(self):
        e=LabEngine();e.clock=1000000
        raw=bytes.fromhex('aa aa de 01 00 92 ff 25 08 8d fe ec ff d1 03 00 00 00 e7')
        e.ingest(P.pack(P.IMU,struct.pack('<BIII',0,0xfffffff0,84,85)+raw))
        self.assertAlmostEqual(e.bus[0],.1);self.assertEqual(e.imu.counts['rvc'],1);e.close()
    def test_demo_fft_mute_record_replay(self):
        e=LabEngine();e.demo()
        a=e.audio.copy();f=np.fft.rfftfreq(len(a),1/e.fs);spec=np.abs(np.fft.rfft(a[:,4]))
        peaks=f[np.argsort(spec)[-4:]];np.testing.assert_allclose(sorted(peaks),[375,750,1125,1500])
        settings=e.voices[1].copy();settings['gate']=False;e.set_voice(1,settings);self.assertTrue(np.all(e.audio[:,1]==0))
        with tempfile.TemporaryDirectory(prefix='中文测试-') as tmp:
            path=Path(tmp)/'record';e.start_record(path);e.stop_record();expected=e.audio.copy()
            e.replay(path);e.thread.join(3);np.testing.assert_array_equal(e.audio,expected)
        e.close();e.imu.disconnect()
    def test_hello_and_error_ack(self):
        e=LabEngine();e.ingest(P.pack(P.INFO,struct.pack('<HIIBH',0,50000000,48000,4,2048)+b'Test'))
        self.assertTrue(e.ready);self.assertEqual(e.device,'Test')
        e.ingest(P.pack(P.ACK,struct.pack('<HB',3,2),1));self.assertEqual(e.status,'握手成功')
        e.pending[3]=(P.VOICE,time.monotonic())
        e.ingest(P.pack(P.ACK,struct.pack('<HB',3,2),2));self.assertIn('拒绝',e.status)
        self.assertEqual(e.command_result(3)['state'],'failed');e.close()

if __name__=='__main__':unittest.main()
