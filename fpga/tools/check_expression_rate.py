"""Prepare/test a report-rate-aware expression extension, separate from frozen FAN03."""
from pathlib import Path
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[2];W=R/'fpga/extensions';O=R/'board-test/expression-rate'
W.mkdir(exist_ok=True);O.mkdir(parents=True,exist_ok=True)
source=R/'fpga/i2cfan03/rtl/hand_expression.v'
s=source.read_text();s=s.replace('// Pose reports requested at 200Hz.', '// Select the actual requested pose report rate (100Hz I2C or 200Hz legacy).')
s=s.replace('module hand_expression(', 'module hand_expression_rate #(parameter POSE_HZ=100)(')
needle='    reg signed [31:0] slow_roll,pitch_lp,high_base,bandpass;'
s=s.replace(needle,'''    // Fixed coefficients for the two supported rates; no runtime divider.
    // Alpha = 1-exp(-2*pi*fc/fs), rounded to Q8.
    localparam SLOW_ALPHA=POSE_HZ==100 ? 16 : 8;
    localparam PITCH_ALPHA=POSE_HZ==100 ? 60 : 32;
    localparam BASE_ALPHA=POSE_HZ==100 ? 44 : 23;
    localparam BAND_ALPHA=POSE_HZ==100 ? 119 : 69;
    localparam HALF_MIN=(POSE_HZ+19)/20-1;
    localparam HALF_MAX=(POSE_HZ+5)/6-1;
    localparam STALE_SAMPLES=POSE_HZ/5;
'''+needle)
s=s.replace('((roll_sample-slow_roll)>>>5)','(((roll_sample-slow_roll)*SLOW_ALPHA)>>>8)')
s=s.replace('((pitch_sample-pitch_lp)>>>3)','(((pitch_sample-pitch_lp)*PITCH_ALPHA)>>>8)')
s=s.replace(')*23)',')*BASE_ALPHA)').replace(')*69)',')*BAND_ALPHA)')
s=s.replace('half_period>=9 && half_period<=34','half_period>=HALF_MIN && half_period<=HALF_MAX')
s=s.replace('half_period>40','half_period>STALE_SAMPLES').replace('half_period<=40','half_period<=STALE_SAMPLES')
module=W/'hand_expression_rate.v';module.write_text(s,encoding='utf8')
tb=(R/'fpga/tb/tb_hand_expression.sv').read_text()
tb=tb.replace('module tb_hand_expression;', 'module tb_hand_expression_rate; parameter POSE_HZ=100;')
tb=tb.replace('hand_expression dut(.*);','hand_expression_rate #(.POSE_HZ(POSE_HZ)) dut(.*);')
start=tb.index('        // Reference stream');end=tb.index('        playable=0;',start)
tb=tb[:start]+'''        // Independently generated sine samples at the declared real report rate.
        // Frequencies 3/5/8/10 must pass; 1/2/12/15 must be rejected.
        for(integer f_index=0;f_index<8;f_index++) begin
            case(f_index)
             0:frequency=1;1:frequency=2;2:frequency=3;3:frequency=5;
             4:frequency=8;5:frequency=10;6:frequency=12;7:frequency=15;
            endcase
            sensor_restarted=1;@(negedge clk);sensor_restarted=0;
            roll=0;pitch=0;express=0;repeat(POSE_HZ)report();express=1;report();
            peak_vibrato=0;observed=0;
            for(n=0;n<POSE_HZ*6;n++) begin
                roll=$rtoi(3*16*$sin(6.283185307179586*frequency*n/POSE_HZ));report();
                if(vibrato_cents< -30 || vibrato_cents>30)$fatal(1,"vibrato limit");
                if(n>POSE_HZ*2 && vibrato_cents!=0)observed++;
                if(vibrato_cents>peak_vibrato)peak_vibrato=vibrato_cents;
            end
            if(frequency>=3 && frequency<=10 && (observed==0 || peak_vibrato<5))
                $fatal(1,"%0dHz report rate failed %0dHz hand tremor peak=%0d",POSE_HZ,frequency,peak_vibrato);
            if((frequency<3 || frequency>10) && observed!=0)
                $fatal(1,"%0dHz report rate accepted %0dHz out-of-band tremor %0d",POSE_HZ,frequency,observed);
            roll=0;repeat(POSE_HZ)report();
            if(vibrato_cents!=0)$fatal(1,"stationary vibrato persists");
            $display("RATE %0d FREQ %0d PEAK %0d ACTIVE %0d",POSE_HZ,frequency,peak_vibrato,observed);
        end
'''+tb[end:]
tb=tb.replace('integer n,peak_vibrato;', 'integer n,peak_vibrato,frequency,observed;')
tb=tb.replace('real 5Hz motion, 1Hz rejection', '3/5/8/10Hz accepted and 1/2/12/15Hz rejected at actual declared rate')
tb=tb.replace('#1000000;', '#10000000;')
test=W/'tb_hand_expression_rate.sv';test.write_text(tb,encoding='utf8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
before={p.relative_to(R).as_posix():sha(p) for p in (module,test,source)}
results={}
for rate in (100,200):
 linux_work='/mnt/'+W.drive[0].lower()+str(W)[2:].replace('\\','/')
 quoted_work="'"+linux_work.replace("'", "'\"'\"'")+"'"
 cmd=f'cd {quoted_work} && iverilog -g2012 -s tb_hand_expression_rate -P tb_hand_expression_rate.POSE_HZ={rate} -o /tmp/expr-rate-{rate} hand_expression_rate.v tb_hand_expression_rate.sv && vvp /tmp/expr-rate-{rate}'
 p=subprocess.run(['wsl','-d','Ubuntu','-e','bash','-lc',cmd],capture_output=True)
 log=p.stdout.decode('utf8',errors='replace')+'\n'+p.stderr.decode('utf8',errors='replace')
 (O/f'rate-{rate}.log').write_text(log,encoding='utf8')
 results[str(rate)]={'passed':p.returncode==0 and 'TB_PASS' in log,'exit_code':p.returncode,
   'messages':[line for line in log.splitlines() if 'FATAL' in line or 'TB_PASS' in line or line.startswith('RATE')]}
 print(rate,results[str(rate)],flush=True)
assert before=={p.relative_to(R).as_posix():sha(p) for p in (module,test,source)}
(O/'validation.json').write_text(json.dumps({'source_sha256':before,'inputs_unchanged':True,
 'tests':results,'integrated_into_current_firmware':False,'physical_tested':False,
 'supported_pose_report_rates':[100,200]},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
raise SystemExit(0 if all(v['passed'] for v in results.values()) else 1)
