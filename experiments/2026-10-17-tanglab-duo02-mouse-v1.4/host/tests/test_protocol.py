import math
import struct
import unittest
from protocol import *

def rvc(seq=222,angles=(1,-110,2085),acc=(-371,-20,977)):
    data=bytes([seq])+struct.pack('<6h',*angles,*acc)+b'\0\0\0'
    return b'\xaa\xaa'+data+bytes([sum(data)&255])

class ProtocolTests(unittest.TestCase):
    def test_rvc_datasheet(self):
        p=RVCParser(); s=p.feed(bytes.fromhex('aaaa de 0100 92ff 2508 8dfe ecff d103 000000 e7'))[0]
        self.assertEqual(s.values[:3],(.01,-1.10,20.85)); self.assertEqual(s.seq,222)
        self.assertAlmostEqual(s.values[3],-.371*9.80665)
    def test_rvc_every_split(self):
        frame=rvc()
        for i in range(len(frame)):
            p=RVCParser(); self.assertEqual(p.feed(frame[:i]),[])
            self.assertEqual(len(p.feed(frame[i:])),1)
    def test_rvc_noise_bad_checksum_and_concat(self):
        bad=bytearray(rvc()); bad[-1]^=1
        p=RVCParser(); out=p.feed(b'noise'+bad+rvc(255)+rvc(0))
        self.assertEqual([s.seq for s in out],[255,0]); self.assertGreater(p.errors,0)
    def test_rvc_bounded_noise(self):
        p=RVCParser(); p.feed(b'x'*100000); self.assertLessEqual(len(p.buf),1)
    def test_shtp_escape_splits(self):
        payload=b'\x7e\x7d\0\xff'; frame=encode_packet(2,255,payload)
        for i in range(len(frame)):
            p=SHTPParser(); out=p.feed(frame[:i])+p.feed(frame[i:]); self.assertEqual(out,[(2,255,payload)])
    def test_shtp_noise_recovery(self):
        p=SHTPParser(); self.assertEqual(p.feed(b'bad\x7e\x01\xff\x7e'),[])
        self.assertEqual(p.feed(encode_packet(3,0,b'a'))[0][2],b'a'); self.assertEqual(p.errors,1)
    def test_shtp_sequence_wrap(self):
        p=SHTPParser(); p.feed(encode_packet(3,255,b'a')+encode_packet(3,0,b'b'))
        self.assertEqual(p.sequence_gaps,0); p.feed(encode_packet(3,2,b'c')); self.assertEqual(p.sequence_gaps,1)
    def test_shtp_timeout_and_bound(self):
        p=SHTPParser(); p.feed(b'\x7e\x01\x7d'); p.expire(); self.assertEqual(p.errors,1)
        p.feed(b'\x7e'+b'x'*40000); self.assertLess(len(p.buf),32769)
        self.assertEqual(len(p.feed(encode_packet(2,0,b'ok'))),1)
    def test_reports_multiple(self):
        payload=b'\xfb'+struct.pack('<i',-1000)+bytes((1,2,3,0))+struct.pack('<hhh',256,-256,0)
        payload+=bytes((8,3,3,0))+struct.pack('<hhhh',0,0,0,16384)
        rows,err=decode_reports(payload); self.assertEqual(err,0)
        self.assertEqual(rows[0].values,(1,-1,0)); self.assertEqual(rows[1].values,(0,0,0,1))
        self.assertEqual(rows[0].sensor_offset_us,100000)
    def test_timebase_rebase_units(self):
        payload=b'\xfb'+struct.pack('<i',100)+b'\xfa'+struct.pack('<i',20)
        payload+=bytes((1,0,3,5))+struct.pack('<hhh',0,0,0)
        self.assertEqual(decode_reports(payload)[0][0].sensor_offset_us,-7500)
    def test_truncated_unknown_invalid_quaternion(self):
        self.assertEqual(decode_reports(b'\x01')[1],1)
        self.assertEqual(decode_reports(b'\xee')[1],1)
        self.assertEqual(decode_reports(b'\x08'+b'\0'*11)[1],1)
    def test_config_interval(self):
        self.assertEqual(len(set_feature(1,500)),17)
        self.assertEqual(struct.unpack_from('<I',set_feature(1,500),5)[0],2000)
        self.assertEqual(struct.unpack_from('<I',set_feature(5,200),5)[0],5000)
        self.assertEqual(struct.unpack_from('<I',set_feature(8,0),5)[0],0)
    def test_config_no_false_success(self):
        t=ConfigTracker(); t.request(5,200,0); t.response(1,10000)
        self.assertIn(5,t.pending); t.expire(6); self.assertIn(5,t.failures)
        t.request(5,200,7); t.response(5,5000); self.assertNotIn(5,t.failures)
        t.request(8,0,8); t.response(8,10000); self.assertIn(8,t.failures)
    def test_pose_known_and_recenter(self):
        q=from_euler(90,0,0); y,p,r=euler(q)
        self.assertAlmostEqual(y,90); self.assertAlmostEqual(p,0)
        self.assertAlmostEqual(euler(relative(q,q))[0],0)
        self.assertAlmostEqual(rotation_matrix(q)[1][0],1)
        for yaw in (-179,179): self.assertAlmostEqual(euler(from_euler(yaw,20,30))[0],yaw)

if __name__=='__main__': unittest.main()
