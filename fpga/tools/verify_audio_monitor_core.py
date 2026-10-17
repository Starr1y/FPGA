"""Read-only aggregate gate for the FFT plus dual-clock observation memory."""
from pathlib import Path
import json
from verify_audio_observer import main as verify_observer,sha
R=Path(__file__).resolve().parents[2];O=R/'board-test/audio-scope'
def main():
 verify_observer();data={}
 for name in ('validation.json','core-validation.json','synthesis-validation.json'):
  d=json.loads((O/name).read_text(encoding='utf8'));assert d['passed'],name
  for n,h in d['source_sha256'].items():assert sha(R/n)==h,(name,n)
  for n,h in d.get('evidence_sha256',{}).items():assert sha(O/n)==h,(name,n)
  for n,h in d.get('report_sha256',{}).items():assert sha(R/n)==h,(name,n)
  assert d['physical_tested'] is False and d['timing_verified'] is False,name
  data[name]=d
 a=data['validation.json'];assert a['pixel_words_checked']==3584 and a['pending_bank_protected'] and a['malformed_frame_rejected'] and a['reset_aborts_partial_frame']
 b=data['core-validation.json'];assert b['complete_stereo_frames']==3 and b['pixel_words_checked']==1536 and b['real_fft_connected']
 assert b['monitor_drops']==b['snapshot_skips']==b['invalid_frames']==0
 assert data['synthesis-validation.json']['board_firmware_generated'] is False
 print('PASS complete audio monitor component evidence: FFT, actual synth PCM, two-clock snapshot, real FFT/pixel words, synthesis; no RGB/board integration yet')
if __name__=='__main__':main()
