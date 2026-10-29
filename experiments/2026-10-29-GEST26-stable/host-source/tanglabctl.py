"""Dependency-free CLI for Codex and Claude Code; no hardware port ownership."""
import argparse,json,sys,time
from pathlib import Path
from urllib.request import Request,OpenerDirector,ProxyHandler,HTTPHandler,HTTPDefaultErrorHandler,HTTPErrorProcessor,HTTPRedirectHandler,UnknownHandler
from urllib.parse import urlsplit
from urllib.error import HTTPError

ROOT=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):raise ValueError('禁止重定向本机会话令牌')

class Client:
    def __init__(self,path):
        data=json.loads(Path(path).read_text(encoding='utf-8-sig'));self.url=data['url'];self.token=data['token']
        parsed=urlsplit(self.url)
        if parsed.scheme!='http' or parsed.hostname!='127.0.0.1' or parsed.username or parsed.path:raise ValueError('只允许本机 127.0.0.1 HTTP 地址')
        # This client only speaks authenticated loopback HTTP. Do not construct
        # urllib's unused HTTPS context (or depend on host OpenSSL settings).
        self.opener=OpenerDirector()
        for handler in (ProxyHandler({}),HTTPHandler(),HTTPDefaultErrorHandler(),NoRedirect(),HTTPErrorProcessor(),UnknownHandler()):
            self.opener.add_handler(handler)
    def request(self,path,data=None):
        wire=None if data is None else json.dumps(data).encode()
        req=Request(self.url+'/api/v1/'+path,data=wire,headers={'Authorization':'Bearer '+self.token,'Content-Type':'application/json'})
        try:
            with self.opener.open(req,timeout=10) as response:return json.load(response)
        except HTTPError as exc:raise RuntimeError(exc.read().decode('utf-8')) from None
    def run(self,action,params,timeout=300,no_wait=False):
        job=self.request('commands',dict(action=action,params=params))
        if no_wait:return job
        end=time.monotonic()+timeout
        while job['state'] not in ('completed','failed','cancelled'):
            if time.monotonic()>end:raise TimeoutError('等待超时；任务仍可查询或取消，编号：'+job['id'])
            time.sleep(.1);job=self.request('jobs/'+job['id'])
        return job

def main():
    p=argparse.ArgumentParser(description='TangLab 本机命令工具：先在 GUI 的 agent 调试页开启接口。')
    p.add_argument('--session',default=str(ROOT/'.agent-session.json'),help='会话信息文件；请勿分享此文件')
    p.add_argument('--timeout',type=float,default=300,help='等待秒数，默认 300')
    p.add_argument('--no-wait',action='store_true',help='提交后立即返回任务编号')
    p.add_argument('command',choices=['status','capabilities','ports','reports','capture-data','spectrum','events','eda','job','cancel','run'],help='查询或执行命令')
    p.add_argument('value',nargs='?',help='run 后为动作名；job/cancel 后为编号；spectrum 后为通道 0～4')
    p.add_argument('--json',default='{}',help='命令参数 JSON，复杂参数建议 --file')
    p.add_argument('--file',help='从 UTF-8 JSON 文件读取命令参数')
    args=p.parse_args()
    try:
        cli=Client(args.session)
        if args.command=='run':
            if not args.value:raise ValueError('run 需要动作名，例如 run demo')
            params=json.loads(Path(args.file).read_text(encoding='utf-8-sig') if args.file else args.json)
            result=cli.run(args.value,params,args.timeout,args.no_wait)
        elif args.command in ('job','cancel'):
            if not args.value:raise ValueError('缺少任务编号')
            result=cli.request('jobs/'+args.value+('/cancel' if args.command=='cancel' else ''),{} if args.command=='cancel' else None)
        else:
            path={'capture-data':'capture','spectrum':'spectrum/'+str(args.value or '4')}.get(args.command,args.command)
            result=cli.request(path)
        print(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False))
        return 1 if isinstance(result,dict) and (result.get('state') in ('failed','cancelled') or result.get('result',{}).get('verdict')=='失败') else 0
    except Exception as exc:
        if __import__('os').environ.get('TANGLAB_DIAGNOSTICS')=='1':
            __import__('traceback').print_exc(file=sys.stderr)
        print(json.dumps(dict(error=str(exc)),ensure_ascii=False));return 2
if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
    sys.exit(main())
