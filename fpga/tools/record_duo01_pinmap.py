"""Record the visually traced NEO schematic pin map and electrical evidence scope."""
from pathlib import Path
import hashlib,json,shutil
R=Path(__file__).resolve().parents[2]
def main():
 source=R/'Tang_Mega_NEO_Dock-138K_31004_Schematics.pdf';ref=R/'docs/reference/Tang_Mega_NEO_Dock_138K_Rev1.4.pdf'
 ref.parent.mkdir(exist_ok=True)
 if source.is_file():shutil.copyfile(source,ref)
 else:assert ref.is_file(),'Missing NEO schematic reference'
 entries=[]
 for hand,rows in enumerate([
  [('SCL','E19',12,'SDRAM0_A1',38),('SDA','C18',18,'SDRAM0_A3',40),('INT','E16',30,'SDRAM0_A4',28),('RST','D20',6,'SDRAM0_A10',36)],
  [('SCL','D19',10,'SDRAM0_A0',37),('SDA','C19',16,'SDRAM0_A2',39),('INT','E17',22,'SDRAM0_~CAS',31),('RST','F16',24,'SDRAM0_~RAS',32)]]):
  for signal,ball,j1,net,j13 in rows:entries.append({'hand':hand,'signal':signal,'fpga_ball':ball,'som_connector':f'J1.{j1}','net':net,'dock_connector':f'J13.{j13}','source_pages':[7,19],'confidence':'high'})
 for signal,ball,j2 in [('BCK','Y17',26),('WS','AB17',28),('DIN','AA16',30),('PA_EN','AB16',36)]:
  entries.append({'signal':signal,'fpga_ball':ball,'som_connector':f'J2.{j2}','source_pages':[7,10],'confidence':'high'})
 data={'source':ref.relative_to(R).as_posix(),'source_sha256':hashlib.sha256(ref.read_bytes()).hexdigest(),
  'schematic_title':'Tang_Mega_138K_Dock(NEO)','revision':'1.4','schematic_date':'2025-03-30','pins':entries,
  'trust_summary':{'pin_routes':'high: visually inspected connector/net/FPGA-ball across sheets',
    'io_standard':'bank2 LVCMOS33 corroborated with existing hardware-tested hand0 constraints; hand1 not physically measured',
    'not_verified':['physical second IMU','new bitstream on board','analog audio','temperature/power','supply-off isolation'],
    'scope':'focused schematic pin tracing, not full PCB/fabrication review'},
  'power_warning':'J13.11 is 5V_Peripheral. Use previously measured 3.3V supply, never derive supply from a GPIO.',
  'audio_format':'PT8211 16-bit LSBJ, WS0 right WS1 left; PA_EN1 amplifier off'}
 out=R/'board-test/duo01/pinmap.json';out.parent.mkdir(exist_ok=True);out.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
if __name__=='__main__':main()
