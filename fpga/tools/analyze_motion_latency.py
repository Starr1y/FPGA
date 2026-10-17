"""Assess external-instrument latency records, never claim physical verification.

No UART, GUI, board control or automatic exclusion of trials. Trace review is a
separate human gate; valid numbers and file hashes cannot prove how data arose.
"""
from pathlib import Path
from decimal import Decimal
import argparse,csv,hashlib,json,re

LIMIT_NS=10_000_000
MIN_TRIALS=1000
FIELDS={'trial_id','hand','reference_ns','onset_ns','outcome','trace_file'}

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def ns_value(value):
    s=(value or '').strip()
    if not re.fullmatch(r'\d+',s):raise ValueError('timestamps must be nonnegative integer nanoseconds')
    n=int(s)
    if n>2**63-1:raise ValueError('timestamp exceeds signed 64-bit range')
    return n

def ms(n):return format(Decimal(n)/Decimal(1_000_000),'f')

def statistics(values):
    if not values:return None
    a=sorted(values);n=len(a)
    median=Decimal(a[n//2]) if n%2 else Decimal(a[n//2-1]+a[n//2])/2
    return {'count':n,'minimum_ms':ms(a[0]),'maximum_ms':ms(a[-1]),
            'mean_ms':format(Decimal(sum(a))/n/1_000_000,'f'),
            'median_ms':format(median/1_000_000,'f'),
            'p95_ms':ms(a[(95*n+99)//100-1]),'p99_ms':ms(a[(99*n+99)//100-1]),
            'percentile_method':'nearest rank, no interpolation or exclusions'}

def assess(csv_path,session_path,firmware_path=None):
    csv_path=Path(csv_path);session_path=Path(session_path)
    result={'schema_version':1,'physical_verified':False,'human_trace_review_required':True,
            'numeric_gate':'INVALID','assessment':'INVALID_INPUT','input_errors':[], 'evidence_errors':[],
            'criteria':{'minimum_trials':MIN_TRIALS,'maximum_latency_ns':LIMIT_NS,'negative_latency_allowed':False,
                        'missed_trial_policy':'retained; blocks numeric pass','excluded_trials':0},
            'provenance':{'records_sha256':digest(csv_path),'session_sha256':digest(session_path)}}
    errors=result['input_errors'];evidence=result['evidence_errors']
    try:session=json.loads(session_path.read_text(encoding='utf-8-sig'))
    except (ValueError,OSError) as e:errors.append('invalid session JSON: '+str(e));return result
    if not isinstance(session,dict):errors.append('session must be an object');return result
    kind=session.get('measurement_kind');result['declared_measurement_kind']=kind
    if kind not in ('physical','synthetic'):errors.append('measurement_kind must be physical or synthetic')
    hands=session.get('hands_expected')
    if not isinstance(hands,list) or not hands or len(set(str(h) for h in hands))!=len(hands) or any(type(h) is not int or h not in (0,1) for h in hands):
        errors.append('hands_expected must be [0], [1] or [0,1]');hands=[]
    minimum=session.get('minimum_trials',MIN_TRIALS)
    if type(minimum) is not int or minimum<MIN_TRIALS:errors.append('minimum_trials cannot be less than 1000');minimum=MIN_TRIALS
    result['criteria']['minimum_trials']=minimum
    reference_count=session.get('reference_count')
    if type(reference_count) is not int or reference_count<0:errors.append('reference_count must state all externally observed actions')
    if session.get('same_instrument_timebase') is not True:errors.append('reference and onset must use the same instrument timebase')
    if session.get('reference_kind') not in ('external_contact','external_optical','external_force','external_motion_sensor'):
        errors.append('reference_kind must be an external physical reference, not a parsed IMU/FPGA/PC event')
    for field in ('reference_channel','analog_channel','analog_onset_method','instrument_model'):
        if not isinstance(session.get(field),str) or not session[field].strip():errors.append(field+' must be specified')
    rate=session.get('instrument_sample_rate_hz')
    if type(rate) not in (int,float) or not 0<rate<1e13:errors.append('instrument_sample_rate_hz must be finite and positive')
    fw_sha=session.get('firmware_sha256')
    if not isinstance(fw_sha,str) or not re.fullmatch(r'[0-9a-f]{64}',fw_sha):errors.append('firmware_sha256 must be a lowercase SHA256')
    traces=session.get('trace_sha256',{})
    if not isinstance(traces,dict):errors.append('trace_sha256 must be a filename-to-hash map');traces={}
    root=(session_path.parent/'raw').resolve()
    rows=[];seen=set();raw_files=set();row_count=0
    with csv_path.open(newline='',encoding='utf-8-sig') as f:
        reader=csv.DictReader(f)
        if not reader.fieldnames or not FIELDS.issubset(reader.fieldnames):errors.append('missing required CSV columns: '+', '.join(sorted(FIELDS)))
        elif len(set(reader.fieldnames))!=len(reader.fieldnames):errors.append('duplicate CSV column names')
        else:
            for row in reader:
                row_count+=1;prefix='CSV line '+str(reader.line_num)+': '
                try:
                    if None in row:raise ValueError('extra unlabelled CSV cells')
                    trial=(row.get('trial_id') or '').strip()
                    if not trial or trial in seen:raise ValueError('missing or duplicate trial_id')
                    seen.add(trial)
                    if (row.get('hand') or '').strip() not in ('0','1'):raise ValueError('hand must be 0 or 1')
                    hand=int(row['hand'])
                    if hand not in hands:raise ValueError('hand is outside the declared test scope')
                    reference=ns_value(row.get('reference_ns'));outcome=(row.get('outcome') or '').strip()
                    onset=(row.get('onset_ns') or '').strip();delay=None
                    if outcome=='hit':
                        delay=ns_value(onset)-reference
                        if delay<0:raise ValueError('negative latency: mismatched clocks/markers')
                    elif outcome=='missed':
                        if onset:raise ValueError('missed trials must have blank onset_ns')
                    else:raise ValueError('outcome must be hit or missed; rows cannot be excluded')
                    name=(row.get('trace_file') or '').strip()
                    if not name:raise ValueError('each action requires a raw trace filename')
                    relative=Path(name)
                    if relative.is_absolute() or relative.drive or '..' in relative.parts:raise ValueError('trace_file must stay below the session raw directory')
                    candidate=(root/name).resolve()
                    if not candidate.is_relative_to(root):raise ValueError('trace_file escapes the session raw directory')
                    raw_files.add(name);rows.append({'hand':hand,'latency_ns':delay,'outcome':outcome})
                except (ValueError,TypeError,OSError) as e:errors.append(prefix+str(e))
    result['counts']={'csv_rows':row_count,'valid_rows':len(rows),'hit':sum(r['outcome']=='hit' for r in rows),
                      'missed':sum(r['outcome']=='missed' for r in rows),'invalid_rows':row_count-len(rows)}
    if reference_count!=row_count:errors.append('CSV row count differs from declared reference_count; keep missing/failed trials as rows')
    if errors:return result  # Never publish partial good-row statistics as a valid dataset.
    values=[r['latency_ns'] for r in rows if r['latency_ns'] is not None]
    result['latency']=statistics(values);result['per_hand']={}
    per_hand_min=minimum//len(hands);result['criteria']['minimum_per_declared_hand']=per_hand_min
    balanced=True
    for hand in hands:
        subset=[r for r in rows if r['hand']==hand];count=len(subset);balanced &= count>=per_hand_min
        result['per_hand'][str(hand)]={'trials':count,'missed':sum(r['outcome']=='missed' for r in subset),
                                    'latency':statistics([r['latency_ns'] for r in subset if r['latency_ns'] is not None])}
    over=sum(v>LIMIT_NS for v in values);result['counts']['over_limit']=over
    passed=row_count>=minimum and balanced and result['counts']['missed']==0 and over==0
    result['numeric_gate']='PASS' if passed else 'FAIL'
    result['both_hands_in_scope']=set(hands)=={0,1}
    result['provenance']['raw_trace_sha256']={}
    for name in sorted(raw_files):
        path=(root/name).resolve();expected=traces.get(name)
        if not isinstance(expected,str) or not re.fullmatch(r'[0-9a-f]{64}',expected):evidence.append('missing/invalid recorded trace hash: '+name)
        if not path.is_file():evidence.append('missing raw trace: '+name);continue
        actual=digest(path);result['provenance']['raw_trace_sha256'][name]=actual
        if actual!=expected:evidence.append('raw trace hash mismatch: '+name)
    if firmware_path is None:evidence.append('supply --firmware to compare recorded identity with the actual FS file')
    else:
        firmware_path=Path(firmware_path)
        if not firmware_path.is_file():evidence.append('firmware file is missing')
        else:
            actual=digest(firmware_path);result['provenance']['actual_firmware_sha256']=actual
            if actual!=fw_sha:evidence.append('firmware hash differs from the session record')
    result['assessment']='NUMERIC_FAIL' if not passed else 'EVIDENCE_INCOMPLETE' if evidence else 'SYNTHETIC_ONLY' if kind=='synthetic' else 'READY_FOR_TRACE_REVIEW'
    result['limitations']=['File integrity and supplied timestamps do not prove physical origin or correct analog onset annotation.',
                          'READY_FOR_TRACE_REVIEW is not a verified physical pass; inspect all raw captures and the stated reference/onset method.',
                          'This report does not certify recognition rate, drift, power safety or a two-hour stability test.']
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('records',type=Path);p.add_argument('session',type=Path)
    p.add_argument('--firmware',type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
    try:data=assess(a.records,a.session,a.firmware)
    except (OSError,UnicodeError,ValueError,csv.Error) as e:
        data={'schema_version':1,'assessment':'INVALID_INPUT','numeric_gate':'INVALID','physical_verified':False,'input_errors':[str(e)]}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf8')
    print(data['assessment']+'; numeric gate='+data['numeric_gate']+'; physical verification remains a separate gate')
    return 0 if data['assessment']=='READY_FOR_TRACE_REVIEW' else 2 if data['assessment']=='INVALID_INPUT' else 1
if __name__=='__main__':raise SystemExit(main())
