"""Bounded local API/CLI + simulated bring-up integration check; no board needed."""
import json,sys,threading,tempfile
from pathlib import Path
from urllib.request import urlopen,Request
from urllib.error import HTTPError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from lab_engine import LabEngine
from lab_agent import CommandController,AgentServer
from tanglabctl import Client

def main():
    base=Path(sys.argv[1]);base.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='agent-check-',dir=base) as temp:
        e=LabEngine();c=CommandController(e,temp);server=AgentServer(c)
        try:
            info=server.start();client=Client(server.session_path)
            try:urlopen(info['url']+'/api/v1/status',timeout=2);raise AssertionError('未授权请求被放行')
            except HTTPError as exc:assert exc.code==401
            job=client.run('demo',{},5);assert job['state']=='completed'
            job=client.run('voices.set',{'voices':[{'channel':0,'hz':-1}]},5);assert job['state']=='failed'
            try:c.wait({'cancel':threading.Event()},lambda:False,.05,'测试超时');raise AssertionError('未超时')
            except TimeoutError:pass
            result=client.run('test.two_voice_spi',{'simulation':True},30)
            assert result['state']=='completed',result
            result=result['result'];assert result['verdict']=='模拟验证完成（非实测）',result
            assert result['simulated'] and not any(x['status']=='失败' for x in result['items'])
            assert any(x['status']=='未执行' and 'SPI' in x['name'] for x in result['items'])
            directory=Path(result['directory']);assert (directory/'双声部.csv').is_file()
            assert (directory/'recording/raw.jsonl').is_file() and (directory/'测试结果.txt').is_file()
            assert all(not v['gate'] for v in e.voices) and e.recorder is None
            summary={'result':'PASS','basis':'模拟，非实物','checks':['身份校验','无效参数','超时','命令结果','两声部流程','导出和回放','SPI 未执行标记','结束清理']}
            (base/'agent-check.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
            print(json.dumps(summary,ensure_ascii=False))
        finally:server.stop();c.shutdown();e.close()
if __name__=='__main__':main()
