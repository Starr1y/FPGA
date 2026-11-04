"""Vision conversion: local rendering, cancellable HTTP, canonical TangScore only."""
import base64, copy, json, re, threading, urllib.request, urllib.error
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit
from PySide6 import QtCore as C, QtGui as G
from PySide6.QtPdf import QPdfDocument
from lab_score import load_score, ASSETS

class Cancelled(Exception): pass

def check_cancel(event):
    if event.is_set(): raise Cancelled('已取消转换，结果不会应用')

def parse_pages(text, count):
    if not text.strip(): return list(range(count))
    pages=set()
    for item in text.replace('，', ',').split(','):
        match=re.fullmatch(r'\s*(\d+)\s*(?:-\s*(\d+)\s*)?',item)
        if not match: raise ValueError('页码格式示例：1-3,5；留空表示全部')
        a=int(match[1]); b=int(match[2] or a)
        if not 1<=a<=b<=count: raise ValueError(f'页码须在1～{count}之间，范围不能倒序')
        pages.update(range(a-1,b))
    return sorted(pages)

class ScoreDocument:
    def __init__(self,path):
        self.path=Path(path); self.pdf=None
        if not self.path.is_file(): raise ValueError('文件不存在')
        if self.path.stat().st_size>64*1024*1024: raise ValueError('谱子文件超过64 MiB，请拆分或压缩')
        if self.path.suffix.lower()=='.pdf':
            self.pdf=QPdfDocument()
            err=self.pdf.load(str(self.path))
            if err!=QPdfDocument.Error.None_:
                raise ValueError('PDF无法打开，可能已加密、损坏或格式不受支持；请先解密或重新导出')
            self.count=self.pdf.pageCount()
            if not self.count: raise ValueError('PDF没有可读取的页面')
        elif self.path.suffix.lower() in ('.png','.jpg','.jpeg','.webp'):
            reader=G.QImageReader(str(self.path)); size=reader.size()
            if not reader.canRead() or size.width()<=0: raise ValueError('图片损坏或无法读取')
            if size.width()*size.height()>100_000_000: raise ValueError('图片像素过大，请先缩小')
            self.count=1
        else: raise ValueError('请选择PNG、JPEG、WebP图片或PDF；JSON请用“导入转换后的文件”')

    def render(self,page,long_edge=2000):
        if not 0<=page<self.count: raise ValueError('页码超出范围')
        if self.pdf:
            size=self.pdf.pagePointSize(page)
            scale=long_edge/max(size.width(),size.height())
            image=self.pdf.render(page,C.QSize(max(1,round(size.width()*scale)),max(1,round(size.height()*scale))))
        else:
            reader=G.QImageReader(str(self.path)); reader.setAutoTransform(True)
            size=reader.size(); size.scale(long_edge,long_edge,C.Qt.AspectRatioMode.KeepAspectRatio)
            reader.setScaledSize(size); image=reader.read()
        if image.isNull(): raise ValueError(f'第{page+1}页渲染失败')
        return image

def data_url(image):
    data=C.QByteArray(); buf=C.QBuffer(data); buf.open(C.QIODevice.OpenModeFlag.WriteOnly)
    if not image.save(buf,'PNG'): raise ValueError('图片编码失败')
    return 'data:image/png;base64,'+base64.b64encode(bytes(data)).decode('ascii')

def endpoint(url):
    url=url.strip().rstrip('/'); parts=urlsplit(url)
    if parts.scheme not in ('http','https') or not parts.netloc or parts.username or parts.password or parts.query or parts.fragment:
        raise ValueError('服务地址须为HTTP/HTTPS地址，不能在地址中填写密钥、查询参数或账号')
    if not parts.path or parts.path=='/': url+='/v1'
    return url if url.endswith('/chat/completions') else url+'/chat/completions'

def parse_output(text):
    text=text.strip()
    if text.startswith('```'):
        match=re.fullmatch(r'```(?:json)?\s*\n(.*?)\n```',text,re.S|re.I)
        if not match: raise ValueError('AI返回的代码围栏不完整，请要求返回单个JSON对象')
        text=match[1]
    try: value=json.loads(text)
    except (ValueError,TypeError) as exc: raise ValueError('AI未返回有效JSON，请检查模型或用外部AI转换后导入') from exc
    return load_score(value)

class VisionAdapter:
    def __init__(self,url,model,key,timeout=90):
        self.url=endpoint(url); self.model=model.strip(); self.key=key.strip(); self.timeout=timeout
        if not self.model or not self.key: raise ValueError('请填写模型名和密钥')
    def __repr__(self): return 'VisionAdapter(密钥隐藏)'
    def request(self,content,event):
        check_cancel(event)
        body=json.dumps({'model':self.model,'messages':[
            {'role':'system','content':(ASSETS/'给AI的转换提示词.txt').read_text(encoding='utf-8')},
            {'role':'user','content':content}], 'stream':False},ensure_ascii=False).encode('utf-8')
        req=urllib.request.Request(self.url,body,{'Authorization':'Bearer '+self.key,'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(req,timeout=self.timeout) as response:
                raw=response.read(4*1024*1024+1)
            check_cancel(event)
            if len(raw)>4*1024*1024: raise ValueError('AI返回内容过大，超过4 MiB')
            response=json.loads(raw)
            text=response['choices'][0]['message']['content']
            if not isinstance(text,str): raise ValueError('模型未返回文本内容')
            return parse_output(text)
        except urllib.error.HTTPError as exc:
            # Never show provider response/request objects: they may echo credentials.
            reason={401:'密钥无效或未授权',403:'无接口权限',404:'服务地址或模型不存在',429:'调用频率或额度受限',400:'请求不被接受，请确认模型支持图片及兼容接口',413:'图片请求过大'}.get(exc.code,'服务端请求失败')
            raise ValueError(f'AI接口错误 HTTP {exc.code}：{reason}') from None
        except (TimeoutError,urllib.error.URLError):
            check_cancel(event); raise ValueError('AI请求超时或网络连接失败，请检查服务地址和网络') from None
        except (KeyError,IndexError,TypeError,json.JSONDecodeError):
            raise ValueError('接口返回结构不兼容，需要Chat Completions视觉模型') from None

def convert(path,pages,url,model,key,event,progress,timeout=90):
    adapter=VisionAdapter(url,model,key,timeout); doc=ScoreDocument(path); merged=None
    try:
        for i,page in enumerate(pages):
            check_cancel(event); progress(i,len(pages),f'正在识别第{page+1}页（{i+1}/{len(pages)}）')
            content=[{'type':'text','text':f'识别文件中的第{page+1}页，按谱面顺序提取单音教学旋律。只转换此页，不重复其他页。返回TangScore JSON；不确定处写入warnings。'},
                     {'type':'image_url','image_url':{'url':data_url(doc.render(page))}}]
            result=adapter.request(content,event); check_cancel(event)
            if merged is None: merged=copy.deepcopy(result); merged['warnings']=[]; merged['steps']=[]
            elif result['tempo_bpm']!=merged['tempo_bpm']:
                raise ValueError('不同页识别到不同速度，首版单一速度格式无法无损合并，请分段转换或用外部AI统一速度')
            merged['steps'].extend(result['steps'])
            merged['warnings'].extend(f'第{page+1}页：{x}' for x in result.get('warnings',[]))
            if len(merged['steps'])>2048: raise ValueError('合并后超过2048步，请缩小页码范围；未截断')
        if merged is None: raise ValueError('没有选择页面')
        if len(pages)>1: merged['warnings'].append('多页按页码顺序合并；请复核跨页连音、反复记号和调号延续。')
        merged['warnings'].append('AI识谱结果必须对照原谱复核；格式检查通过不代表识谱准确。')
        check_cancel(event); return load_score(merged)
    finally:
        if doc.pdf: doc.pdf.close()

class ConversionWorker(C.QObject):
    progress=C.Signal(int,int,str)
    completed=C.Signal(int,object,str)
    def __init__(self,parent=None):
        super().__init__(parent); self.cancel_event=threading.Event()
    def start(self,revision,path,pages,url,model,key):
        def work():
            try:
                result=convert(path,pages,url,model,key,self.cancel_event,self.progress.emit)
                if not self.cancel_event.is_set(): self.completed.emit(revision,result,'')
            except Cancelled: pass
            except Exception as exc:
                if not self.cancel_event.is_set(): self.completed.emit(revision,None,str(exc).replace(key,'[密钥隐藏]')[:600] if key else str(exc)[:600])
        self.thread=threading.Thread(target=work,daemon=True); self.thread.start()
    def cancel(self): self.cancel_event.set()
