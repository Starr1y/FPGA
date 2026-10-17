"""Strict analyzer regression using synthetic files only, never physical evidence."""
import csv,json,tempfile,unittest
from pathlib import Path
from analyze_motion_latency import assess,digest

class AnalyzerChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='tanglab-latency-synthetic-');self.root=Path(self.temp.name)
        (self.root/'raw').mkdir();self.trace=self.root/'raw/synthetic-capture.csv';self.trace.write_text('SYNTHETIC ANALYZER FIXTURE ONLY\n')
        self.firmware=self.root/'synthetic.fs';self.firmware.write_bytes(b'SYNTHETIC_NOT_A_BITSTREAM')
        self.meta={'measurement_kind':'synthetic','hands_expected':[0,1],'minimum_trials':1000,'reference_count':1000,
                   'same_instrument_timebase':True,'reference_kind':'external_contact','reference_channel':'synthetic D0',
                   'analog_channel':'synthetic A1','analog_onset_method':'synthetic threshold for parser test only',
                   'instrument_model':'SYNTHETIC FIXTURE, NOT AN INSTRUMENT','instrument_sample_rate_hz':1000000,
                   'firmware_sha256':digest(self.firmware),'trace_sha256':{'synthetic-capture.csv':digest(self.trace)}}
        self.rows=[]
        for i in range(1000):
            delay=1_000_000 if i<949 else 5_000_000 if i<999 else 10_000_000
            self.rows.append({'trial_id':str(i),'hand':i%2,'reference_ns':i*1_000_000_000,'onset_ns':i*1_000_000_000+delay,
                              'outcome':'hit','trace_file':'synthetic-capture.csv'})
    def tearDown(self):self.temp.cleanup()
    def run_data(self):
        csv_path=self.root/'records.csv';meta_path=self.root/'session.json'
        with csv_path.open('w',newline='',encoding='utf8') as f:
            w=csv.DictWriter(f,fieldnames=list(self.rows[0]));w.writeheader();w.writerows(self.rows)
        meta_path.write_text(json.dumps(self.meta),encoding='utf8')
        return assess(csv_path,meta_path,self.firmware)
    def test_exact_stats_and_synthetic_cannot_certify_physical(self):
        d=self.run_data();self.assertEqual(d['numeric_gate'],'PASS');self.assertEqual(d['assessment'],'SYNTHETIC_ONLY')
        self.assertEqual(d['latency']['mean_ms'],'1.209');self.assertEqual(d['latency']['median_ms'],'1')
        self.assertEqual(d['latency']['p95_ms'],'5');self.assertEqual(d['latency']['p99_ms'],'5');self.assertEqual(d['latency']['maximum_ms'],'10')
        self.assertEqual(d['per_hand']['0']['trials'],500);self.assertFalse(d['physical_verified'])
    def test_one_ns_over_limit_is_not_rounded_away(self):
        self.rows[-1]['onset_ns']+=1;d=self.run_data();self.assertEqual(d['numeric_gate'],'FAIL');self.assertEqual(d['counts']['over_limit'],1)
    def test_missed_trial_stays_in_denominator(self):
        self.rows[10]['outcome']='missed';self.rows[10]['onset_ns']='';d=self.run_data()
        self.assertEqual(d['counts']['csv_rows'],1000);self.assertEqual(d['counts']['missed'],1);self.assertEqual(d['numeric_gate'],'FAIL')
    def test_negative_nan_duplicate_and_undeclared_hand_invalidate_whole_dataset(self):
        for field,value in [('onset_ns',-1),('reference_ns','NaN'),('trial_id','0'),('hand',2)]:
            original=self.rows[1][field];self.rows[1][field]=value;d=self.run_data();self.rows[1][field]=original
            self.assertEqual(d['assessment'],'INVALID_INPUT');self.assertNotIn('latency',d)
    def test_missing_trial_and_hand_imbalance_cannot_pass(self):
        self.rows.pop();d=self.run_data();self.assertEqual(d['assessment'],'INVALID_INPUT')
        self.meta['reference_count']=999;d=self.run_data();self.assertEqual(d['numeric_gate'],'FAIL')
        for row in self.rows:row['hand']=0
        d=self.run_data();self.assertEqual(d['numeric_gate'],'FAIL');self.assertEqual(d['per_hand']['1']['trials'],0)
    def test_trace_firmware_mutation_and_no_software_reference(self):
        self.trace.write_text('tampered');d=self.run_data();self.assertEqual(d['assessment'],'EVIDENCE_INCOMPLETE')
        self.assertTrue(any('trace hash mismatch' in s for s in d['evidence_errors']))
        self.firmware.write_bytes(b'changed');d=self.run_data();self.assertTrue(any('firmware hash differs' in s for s in d['evidence_errors']))
        self.meta['reference_kind']='fpga_note_event';d=self.run_data();self.assertEqual(d['assessment'],'INVALID_INPUT')
    def test_traversal_is_rejected_and_physical_claim_still_requires_review(self):
        self.rows[0]['trace_file']='../synthetic.fs';self.assertEqual(self.run_data()['assessment'],'INVALID_INPUT')
        self.rows[0]['trace_file']='synthetic-capture.csv';self.meta['measurement_kind']='physical';d=self.run_data()
        self.assertEqual(d['assessment'],'READY_FOR_TRACE_REVIEW');self.assertFalse(d['physical_verified']);self.assertTrue(d['human_trace_review_required'])

if __name__=='__main__':unittest.main(verbosity=2)
