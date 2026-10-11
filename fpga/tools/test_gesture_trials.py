"""Check counting semantics with synthetic CSVs; these are not physical results."""
import csv,tempfile
from pathlib import Path
from analyse_gesture_trials import FIELDS,analyse

with tempfile.TemporaryDirectory() as temp:
 p=Path(temp)/'synthetic.csv';rows=[]
 for intent in ('hit','nonhit'):
  for n in range(100):
   delta=(0 if n<2 else 1) if intent=='hit' else (1 if n<2 else 0)
   rows.append(dict(zip(FIELDS,['synthetic-person','synthetic-hand','a'*64,f'{intent}-{n}',intent,'3','10',str(10+delta),'3','T1' if delta else 'T0','synthetic fixture only'])))
 def save():
  with p.open('w',encoding='utf-8-sig',newline='') as f:
   writer=csv.DictWriter(f,fieldnames=FIELDS);writer.writeheader();writer.writerows(rows)
 save();d=analyse(p);g=d['groups'][0]
 assert g['successful_hits']==98 and g['false_trigger_trials']==2 and g['gesture_acceptance_passed']
 rows[100]['hits_after']='12';save();assert not analyse(p)['groups'][0]['gesture_acceptance_passed']
 rows[100]['hits_after']='11'
 # Duplicate firing is not a successful hit, even if the selected zone is correct.
 rows[2]['hits_after']='12';save();assert not analyse(p)['groups'][0]['gesture_acceptance_passed']
 rows[2]['hits_after']='11';rows[102]['hits_after']='11';save();assert not analyse(p)['groups'][0]['gesture_acceptance_passed']
 # Missing or mixed-version rows cannot provide evidence for one complete run.
 rows[0]['firmware_sha256']='b'*64;save();assert not analyse(p)['all_complete_groups_passed']
 rows[0]['firmware_sha256']='a'*64;rows[1]['hits_after']='';save();assert analyse(p)['incomplete_csv_lines']
 rows[1]['hits_after']='9';save()
 try:analyse(p);raise AssertionError('reset counts accepted')
 except ValueError:pass
print('PASS synthetic statistics: 98/100 boundary, <=2 false trials, duplicates, missing/mixed versions, reset rejection; no physical claim')
