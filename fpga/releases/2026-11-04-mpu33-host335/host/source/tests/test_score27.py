import unittest,json,tempfile,struct,zlib,threading
from pathlib import Path
from lab_score import load_score,compile_score,validate_ai_output,AIConversionAdapter,ASSETS

class ScoreTests(unittest.TestCase):
    def setUp(self):self.s=load_score(ASSETS/'左右手练习.tangscore.json')
    def test_bad_formats(self):
        for key,value in [('format','x'),('version',2),('tempo_bpm',True),('steps',[]),('extra',1)]:
            v=dict(self.s);v[key]=value
            with self.assertRaises(ValueError):load_score(v)
        for n in (-1,128,True):
            v=load_score(self.s);v['steps'][0]['midi']=n
            with self.assertRaises(ValueError):load_score(v)
        v=load_score(self.s);v['steps']=[v['steps'][0]]*2049
        with self.assertRaises(ValueError):load_score(v)
    def test_range_and_layout(self):
        s=load_score(self.s);s['steps']=[dict(hand='left',midi=n,duration_ticks=480) for n in (0,127)]
        o=compile_score(s);self.assertTrue(o['requires_confirmation']);self.assertTrue(all(36<=r['midi']<=83 for r in o['rows']))
        self.assertEqual(o['crc32'],zlib.crc32(struct.pack('<2I',*o['words'])))
        with self.assertRaises(ValueError):compile_score(ASSETS/'半音练习.tangscore.json',0)
        with self.assertRaises(ValueError):compile_score(self.s,1)
    def test_paths_ai(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'中文曲谱.tangscore.json';p.write_text(json.dumps(self.s,ensure_ascii=False),encoding='utf8');self.assertEqual(load_score(p),self.s)
        for text in ('```json\n{}\n```','{}','{"format":"wrong"}'):
            with self.assertRaises(ValueError):validate_ai_output(text)
        a=AIConversionAdapter(key='do-not-log');self.assertNotIn('do-not-log',repr(a));self.assertNotIn('key',a.public_settings())
        with self.assertRaises(ValueError):a.convert('missing.png',[0],threading.Event(),lambda *a:None)
    def test_full_size_and_clamp(self):
        s=load_score(self.s);s['steps']=[dict(hand='right',midi=60,duration_ticks=1)]*2048
        o=compile_score(s);self.assertEqual(o['count'],2048);self.assertTrue(o['requires_confirmation']);self.assertEqual(o['rows'][0]['hold_ms'],100)
if __name__=='__main__':unittest.main()
