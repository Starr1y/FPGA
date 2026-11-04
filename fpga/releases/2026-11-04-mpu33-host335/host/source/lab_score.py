"""TangScore v1: validated canonical input -> deterministic board words."""
import json,struct,zlib,copy,math
from pathlib import Path
from jsonschema import Draft202012Validator

ASSETS=Path(__file__).with_name('score_assets')
SCHEMA=json.loads((ASSETS/'tangscore.schema.json').read_text(encoding='utf8'))
VALIDATOR=Draft202012Validator(SCHEMA)
LAYOUTS=((0,2,4,5,7,9,11),(0,2,4,7,9),tuple(range(12)))
OCTAVE_CODES={2:2,3:3,4:0,5:1}
NAMES=('C','C#','D','D#','E','F','F#','G','G#','A','A#','B')

def note_name(n):return f'{NAMES[n%12]}{n//12-1}'

def load_score(value):
    if isinstance(value,(str,Path)):
        path=Path(value)
        if path.stat().st_size>1048576:raise ValueError('曲谱文件超过1 MiB')
        try:value=json.loads(path.read_text(encoding='utf-8-sig'))
        except (UnicodeError,json.JSONDecodeError) as exc:raise ValueError('需要UTF-8标准JSON曲谱：'+str(exc)) from exc
    if isinstance(value,dict) and value.get('version')==2:
        simple_validator=Draft202012Validator(json.loads((ASSETS/'tangscore-v2.schema.json').read_text(encoding='utf8')))
        simple_errors=sorted(simple_validator.iter_errors(value),key=lambda x:str(list(x.path)))
        if simple_errors:raise ValueError('简化曲谱校验失败：'+simple_errors[0].message)
        value=copy.deepcopy(value)
        tempo=value['tempo_bpm']
        for step in value['steps']:
            step['duration_ticks']=max(1,round(step.pop('hold_ms')*tempo*480/60000))
            if 'rest_ms' in step:step['rest_before_ticks']=round(step.pop('rest_ms')*tempo*480/60000)
        value['version']=1;value['ticks_per_quarter']=480
    errors=sorted(VALIDATOR.iter_errors(value),key=lambda x:str(list(x.path)))
    if errors:
        e=errors[0];raise ValueError('曲谱校验失败 '+'.'.join(map(str,e.path))+': '+e.message)
    # jsonschema considers booleans distinct from integer; forbid non-finite input too.
    return copy.deepcopy(value)

def compile_score(value,layout='auto'):
    score=load_score(value);notes=[x['midi'] for x in score['steps']]
    lo,hi=min(notes),max(notes);candidates=[k for k in range(-10,11) if lo+12*k>=48 and hi+12*k<=83]
    shift=min(candidates,key=lambda k:(abs(k),k)) if candidates else 0
    changes=[];rows=[];adapted=copy.deepcopy(score);pcs=set()
    for i,step in enumerate(score['steps']):
        n=step['midi']+12*shift
        while n<48:n+=12
        while n>83:n-=12
        ms=round(step['duration_ticks']*60000/(score['tempo_bpm']*480));hold=max(100,min(10000,ms))
        if n!=step['midi']:changes.append(f'第{i+1}步 {note_name(step["midi"])} → {note_name(n)}（八度适配）')
        if hold!=ms:changes.append(f'第{i+1}步发声保持 {ms}ms → {hold}ms（硬件100～10000ms）')
        if n!=step['midi']:adapted['steps'][i]['original_midi']=step.get('original_midi',step['midi'])
        adapted['steps'][i]['midi']=n;pcs.add(n%12)
        rows.append(dict(index=i,hand=step['hand'],original_midi=step.get('original_midi',step['midi']),midi=n,note=note_name(n),hold_ms=hold,duration_ticks=step['duration_ticks'],rest_before_ticks=step.get('rest_before_ticks',0)))
    profile=0 if pcs<=set(LAYOUTS[0]) else 2
    if layout!='auto':
        if type(layout) is not int or layout not in (0,1,2):raise ValueError('布局须为auto或0/1/2')
        profile=layout
    if not pcs<=set(LAYOUTS[profile]):raise ValueError('当前布局无法准确表示全部音符，请使用十二音；不会改为邻近音')
    words=[]
    for row in rows:
        n=row['midi'];zone=LAYOUTS[profile].index(n%12);code=OCTAVE_CODES[n//12-1]
        row.update(zone=zone,octave=code,profile=profile)
        words.append((row['hold_ms']<<16)|(n<<9)|((row['hand']=='right')<<8)|(zone<<4)|(code<<2)|profile)
    wire=struct.pack('<'+'I'*len(words),*words);checksum=zlib.crc32(wire)&0xffffffff
    return dict(score=score,adapted=adapted,profile=profile,rows=rows,words=words,crc32=checksum,count=len(words),changes=changes,requires_confirmation=bool(changes),warnings=list(score.get('warnings',[])),octave_shift=shift)

def validate_ai_output(text):
    from lab_score_ai import parse_output
    return parse_output(text)

class AIConversionAdapter:
    """Compatibility wrapper for the implemented vision adapter."""
    def __init__(self,url='',model='',key=''):self.url=url;self.model=model;self._key=key
    def __repr__(self):return 'AIConversionAdapter(密钥隐藏)'
    def public_settings(self):return dict(url=self.url,model=self.model,enabled=bool(self.url and self.model and self._key))
    def convert(self,path,pages,event,progress):
        from lab_score_ai import convert
        return convert(path,pages,self.url,self.model,self._key,event,progress)
