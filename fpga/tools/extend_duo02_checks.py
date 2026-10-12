"""One-time assembly of DUO02 checks from preserved DUO01 fixtures."""
from pathlib import Path
R=Path(__file__).resolve().parents[2];W=R/'fpga/duo02'
for src,dst in [('duo01_release.py','duo02_release.py'),('check_duo_audio.py','check_duo02_audio.py'),('check_duo_board.py','check_duo02_board.py'),('package_duo01.py','package_duo02.py')]:
 p=R/'fpga/tools'/dst;assert not p.exists(),dst
 s=(R/'fpga/tools'/src).read_text(encoding='utf8').replace('duo01','duo02').replace('DUO01','DUO02')
 if dst=='check_duo02_audio.py':
  s=s.replace("[R/'fpga/dualhand/tb'/n for n in ['tb_dual_note_map.sv','tb_dual_synth.sv']]","[R/'fpga/dualhand/tb/tb_dual_note_map.sv',W/'tb/tb_dual_synth.sv']")
 p.write_text(s,encoding='utf8')
s=(R/'fpga/dualhand/tb/tb_dual_synth.sv').read_text(encoding='utf8')
s=s.replace('wire[79:0]samples;','wire signed[15:0]stereo_left,stereo_right;wire[31:0]stereo_clips;\n wire[79:0]samples;')
s=s.replace('.samples(samples),.sample_valid(sample_valid)', '.samples(samples),.stereo_left(stereo_left),.stereo_right(stereo_right),.stereo_clips(stereo_clips),.sample_valid(sample_valid)')
s=s.replace('reg[31:0]right_freq;', '''// Independent reference: sum the exported per-Voice samples by ownership bank.
 integer reference_left,reference_right,stereo_frames=0,different_frames=0;
 function signed[15:0]limit16(input integer n);begin limit16=n>32767 ? 32767 : n< -32768 ? -32768 : n;end endfunction
 always @(negedge clk)if(rst_n && sample_valid)begin
  reference_left=0;reference_right=0;
  for(integer v=0;v<VOICES;v++)begin
   if(v<BANK)reference_left+=$signed(voice_samples[v*16+:16]);
   else reference_right+=$signed(voice_samples[v*16+:16]);
  end
  reference_left=reference_left >>> (VOICES==32 ? 3 : 1);
  reference_right=reference_right >>> (VOICES==32 ? 3 : 1);
  if(stereo_left!==limit16(reference_left) || stereo_right!==limit16(reference_right))$fatal(1,"independent stereo bank mix mismatch");
  stereo_frames++;if(stereo_left!=stereo_right)different_frames++;
 end
 reg[31:0]right_freq;''')
s=s.replace('pair(6,0,7,10,2,7,80,0);settle();', '''single(0,3,0,1,100,0);wait_samples(60);
  if(stereo_left==0 || stereo_right!=0)$fatal(1,"single hand must not leak into the other dry channel");
  @(negedge clk);rst_n=0;repeat(5)@(negedge clk);rst_n=1;
  pair(6,0,7,10,2,7,80,0);settle();''',1)
s=s.replace('$display("TB_PASS %0d Voices:', 'if(stereo_frames<500 || different_frames<100)$fatal(1,"stereo coverage missing");\n  $display("TB_PASS %0d Voices: independent left/right bank PCM,')
(W/'tb/tb_dual_synth.sv').write_text(s,encoding='utf8')
s=(R/'fpga/dualhand/tb/tb_duo_board.sv').read_text(encoding='utf8').replace('top_duo01','top_duo02').replace('DUO01','DUO02').replace('module tb_duo_board;','module tb_duo02_board;')
s=s.replace('dut.pcm!=0','dut.pcm_left!=0 || dut.pcm_right!=0')
s=s.replace('if(dut.underflows || dut.invalid || dut.drops || dut.overruns)', 'if(dut.underflows || dut.invalid || dut.drops || dut.overruns || dut.fx_drops)')
s=s.replace('reg[31:0]right_frequency;', 'reg[31:0]right_frequency;')
(R/'fpga/dualhand/tb/tb_duo02_board.sv').write_text(s,encoding='utf8')
p=R/'fpga/tools/check_duo02_board.py';s=p.read_text(encoding='utf8').replace('tb_duo_board','tb_duo02_board');p.write_text(s,encoding='utf8')
p=R/'fpga/tools/package_duo02.py';s=p.read_text(encoding='utf8').replace("'16-bit mono duplicated L/R, PT8211 LSBJ 48kHz'","'independent 16-bit stereo with switchable delay/chorus/reverb, PT8211 LSBJ 48kHz'");p.write_text(s,encoding='utf8')
O=R/'board-test/duo02';O.mkdir(parents=True,exist_ok=True)
(O/'pinmap.json').write_bytes((R/'board-test/duo01/pinmap.json').read_bytes())
print('Assembled DUO02 checks; source bank reference and native board fixtures')
