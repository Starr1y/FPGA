"""Read-only integrity gate for observer numeric, real-synth and synthesis evidence."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[2];O=R/'board-test/audio-monitor'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 data={}
 for name in ('validation.json','synth-path-validation.json','synthesis-validation.json'):
  d=json.loads((O/name).read_text(encoding='utf8'));assert d['passed'],name
  for n,h in d['source_sha256'].items():assert sha(R/n)==h,(name,n)
  for n,h in d.get('evidence_sha256',{}).items():assert sha(O/n)==h,(name,n)
  for n,h in d.get('report_sha256',{}).items():assert sha(R/n)==h,(name,n)
  assert d['physical_tested'] is False and d['timing_verified'] is False,name
  data[name]=d
 d=data['validation.json'];assert d['integer_bit_exact'] and d['overload_and_reset_checked']
 assert d['native_stereo_frames']==9 and d['complex_bins_checked']==12312 and d['wave_columns_checked']==1536
 assert d['cycles_per_stereo_frame']<200000 and d['max_complex_error_q8']<256
 assert data['synth-path-validation.json']['complete_stereo_frames']>=2
 assert data['synthesis-validation.json']['board_firmware_generated'] is False
 print('PASS FFT observer: numeric/reference, actual 32-Voice PCM tap, component synthesis hashes; board integration and physical proof still pending')
if __name__=='__main__':main()
