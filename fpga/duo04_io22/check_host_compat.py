"""Parse simulated UART bytes with the latest, unmodified host. Opens no serial port.
Usage: python check_host_compat.py PATH_TO_HOST_SOURCE [UART_HEX]
"""
from pathlib import Path
import sys, json

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(Path(sys.argv[1]).resolve()))
from lab_engine import LabEngine
data=bytes.fromhex(Path(sys.argv[2] if len(sys.argv)>2 else ROOT/'hello_wire.hex').read_text())
engine=LabEngine()
frames=list(engine.parser.feed(data))
for f in frames:
    engine.frame(f)
assert engine.ready and engine.device=='DUO04-LIVE 2.1+IO22'
assert engine.capabilities.get('interaction_v21') and engine.capabilities.get('instrument')
assert engine.parser.errors==0
print(json.dumps({'status':'PASS','source':'RTL UART simulation, no serial port',
 'device':engine.device,'frames':len(frames),'crc_errors':engine.parser.errors,
 'latest_host_interaction_enabled':engine.capabilities['interaction_v21']},ensure_ascii=False,indent=2))
