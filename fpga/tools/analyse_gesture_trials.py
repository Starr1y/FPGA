"""Summarize measured gesture trials; never infer physical results from RTL tests."""
import argparse,csv,json
from pathlib import Path
from collections import defaultdict

FIELDS=['person','hand','firmware_sha256','trial','intent','expected_zone','hits_before','hits_after','actual_zone','trigger_reason','notes']

def analyse(path):
 groups=defaultdict(list);incomplete=[]
 with path.open(encoding='utf-8-sig',newline='') as file:
  reader=csv.DictReader(file)
  if reader.fieldnames!=FIELDS:raise ValueError('CSV columns must match the supplied template')
  for line,row in enumerate(reader,2):
   if not any(row.values()):continue
   required=['person','hand','firmware_sha256','trial','intent','hits_before','hits_after']
   if any(not row[k].strip() for k in required):incomplete.append(line);continue
   if row['intent'] not in ('hit','nonhit'):raise ValueError(f'line {line}: intent must be hit or nonhit')
   firmware=row['firmware_sha256'].strip().lower()
   if len(firmware)!=64 or any(c not in '0123456789abcdef' for c in firmware):raise ValueError(f'line {line}: invalid firmware SHA256')
   before,after=int(row['hits_before']),int(row['hits_after'])
   if not 0<=before<=after<=0xffffffff:raise ValueError(f'line {line}: reset/wrapped/invalid counts; repeat this trial separately')
   key=(row['person'],row['hand'],firmware)
   if any(old['trial']==row['trial'] for old in groups[key]):raise ValueError(f'line {line}: duplicate trial')
   delta=after-before
   if row['intent']=='hit':
    if not row['expected_zone'] or not row['actual_zone'] or not row['trigger_reason']:
     incomplete.append(line);continue
    expected,actual=int(row['expected_zone']),int(row['actual_zone'])
    if not 0<=expected<12 or not 0<=actual<12:raise ValueError(f'line {line}: invalid zone')
    if row['trigger_reason'] not in ('T0','T1','T2','T3'):raise ValueError(f'line {line}: invalid trigger reason')
    accepted=delta==1 and actual==expected and row['trigger_reason']!='T0'
   else:accepted=delta==0
   groups[key].append({'trial':row['trial'],'intent':row['intent'],'event_delta':delta,'passed':accepted})
 result=[]
 for (person,hand,firmware),rows in sorted(groups.items()):
  hits=[r for r in rows if r['intent']=='hit'];nonhits=[r for r in rows if r['intent']=='nonhit']
  success=sum(r['passed'] for r in hits);false_trials=sum(not r['passed'] for r in nonhits)
  hit_rate=success/len(hits) if hits else None
  # Count every false event: repeated firing in one trial cannot be hidden.
  false_rate=false_trials/len(nonhits) if nonhits else None
  false_events=sum(r['event_delta'] for r in nonhits)
  false_event_rate=false_events/len(nonhits) if nonhits else None
  count_met=len(hits)>=100 and len(nonhits)>=100
  result.append({'person':person,'hand':hand,'firmware_sha256':firmware,'hit_trials':len(hits),
   'successful_hits':success,'recognition_rate':hit_rate,'nonhit_trials':len(nonhits),
   'false_trigger_trials':false_trials,'false_trigger_events':false_events,
   'false_trigger_trial_rate':false_rate,'false_trigger_events_per_nonhit_trial':false_event_rate,
   'minimum_trial_count_met':count_met,
   'gesture_acceptance_passed':count_met and hit_rate>=0.98 and false_event_rate<=0.02,
   'trials':rows})
 return {'source_csv':str(path.resolve()),'measurement_source':'human recorded physical observations; not automatically verified',
  'incomplete_csv_lines':incomplete,'groups':result,'all_complete_groups_passed':bool(result) and not incomplete and all(g['gesture_acceptance_passed'] for g in result),
  'latency_verified':False,'two_hour_stability_verified':False,'full_task_complete':False}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('csv',type=Path);parser.add_argument('--template',action='store_true');parser.add_argument('--output',type=Path)
 args=parser.parse_args()
 if args.template:
  if args.csv.exists():raise FileExistsError('Preserve existing observations')
  args.csv.parent.mkdir(parents=True,exist_ok=True)
  with args.csv.open('w',encoding='utf-8-sig',newline='') as file:csv.writer(file).writerow(FIELDS)
  print('Created header-only physical-trial template; no observations were fabricated');return
 data=analyse(args.csv);encoded=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
 if args.output:
  args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(encoded,encoding='utf8')
 print(encoded)

if __name__=='__main__':main()
