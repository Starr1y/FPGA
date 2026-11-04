// GY-521 acquisition: independent I2C bus, auto probe68/69, 200Hz.
// Registers per TDK RM-MPU-6000A: DLPF3, divider4, gyro1000dps, accel8g.
// Output units match the existing instrument: quaternionQ14, gyroQ9rad/s,
// accelerationQ8m/s2. Compatibility accuracy=2 means local filter READY,
// not a sensor-provided BNO calibration accuracy.
module mpu6050_host_reference #(
 parameter REPORT_BACKPRESSURE=1,CLK_HZ=50000000,HALF_DIV=100,
 parameter RESET_TICKS=CLK_HZ/100,BOOT_TICKS=CLK_HZ*3/4,RESET_SETUP_TICKS=CLK_HZ/100,
 parameter BIAS_LOG2=8,WARMUP_SAMPLES=600
)(input clk,rst_n,force_reset,miso,scl_in,int_n,linear_ready,quat_ready,
 output[31:0]timestamp_now,output sck,mosi,sensor_rst_n,
 output reg fault_latched,online,sensor_restarted,output[4:0]feature_mask,
 output reg[31:0]reset_attempts,protocol_errors,sequence_gaps,
 output reg[7:0]quat_sequence,linear_sequence,output reg[31:0]quat_timestamp_ticks,linear_timestamp_ticks,
 output quat_timestamp_valid,linear_timestamp_valid,
 output reg quat_valid,accel_valid,gyro_valid,gravity_valid,linear_valid,
 output signed[15:0]qx,qy,qz,qw,ax,ay,az,gx,gy,gz,gravity_x,gravity_y,gravity_z,lx,ly,lz,
 output reg[15:0]pose_hz,accel_hz,gyro_hz,received_packets,received_bytes,
 output[1:0]accuracy,output reg[3:0]first_failure_reason,failure_reason,
 output[15:0]failure_header,output[1:0]failure_inputs
);
 localparam US_DIV=CLK_HZ/1000000>0 ? CLK_HZ/1000000 : 1;
 reg[31:0]divider,time_us,time_ticks,timer,rate_timer,last_sample_us,age;
 reg[6:0]address;
 reg[6:0]hundred;reg[15:0]rate_count;
 assign timestamp_now=time_ticks;assign sensor_rst_n=1'b1;
 assign feature_mask=online ? 5'b11111 : 0;
 assign failure_header={8'h75,1'b0,address};assign failure_inputs={scl_in,miso};
 assign quat_timestamp_valid=1;assign linear_timestamp_valid=1;
 wire ready,fb_busy,fb_done;wire[31:0]fusion_overruns;
 assign accuracy=ready ? 2'd2 : 2'd0;
 reg[4:0]state,after_transaction;reg[3:0]config_index;
 reg alternate;
 reg request,read_op;reg[7:0]reg_address,write_value;reg[4:0]read_count;
 wire busy,done;wire[3:0]error;wire[111:0]data;
 wire transport_rst=rst_n && !force_reset && state!=16;
 mpu6050_registers #(.HALF_DIV(HALF_DIV),.TIMEOUT(CLK_HZ/40)) bus(
 .clk(clk),.rst_n(transport_rst),.start(request),.read_op(read_op),.address(address),
 .register_address(reg_address),.write_value(write_value),.read_count(read_count),
 .scl_in(scl_in),.sda_in(miso),.scl_low(sck),.sda_low(mosi),.busy(busy),.done(done),.error(error),.data(data));
 function[7:0]cfg_addr;input[3:0]idx;begin case(idx)
 0:cfg_addr=8'h6b;1:cfg_addr=8'h6c;2:cfg_addr=8'h1a;3:cfg_addr=8'h19;
 4:cfg_addr=8'h1b;5:cfg_addr=8'h1c;6:cfg_addr=8'h23;7:cfg_addr=8'h6a;8:cfg_addr=8'h37;default:cfg_addr=8'h38;
 endcase end endfunction
 function[7:0]cfg_value;input[3:0]idx;begin case(idx)
 0:cfg_value=1;2:cfg_value=3;3:cfg_value=4;4,5:cfg_value=8'h10;9:cfg_value=1;default:cfg_value=0;
 endcase end endfunction
 reg fstart;reg signed[15:0]rax,ray,raz,rgx,rgy,rgz;reg[15:0]dt_us;
 mpu6050_fusion #(.BIAS_LOG2(BIAS_LOG2),.WARMUP_SAMPLES(WARMUP_SAMPLES)) fusion(
 .clk(clk),.rst_n(rst_n && !force_reset && online),.start(fstart),.ax_raw(rax),.ay_raw(ray),.az_raw(raz),.gx_raw(rgx),.gy_raw(rgy),.gz_raw(rgz),.dt_us(dt_us),
 .busy(fb_busy),.done(fb_done),.ready(ready),.qx(qx),.qy(qy),.qz(qz),.qw(qw),
 .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.gravity_x(gravity_x),.gravity_y(gravity_y),.gravity_z(gravity_z),.lx(lx),.ly(ly),.lz(lz),.overruns(fusion_overruns));
 task transaction;input reading;input[7:0]regno,val;input[4:0]n;input[4:0]next_state;
 begin request<=1;read_op<=reading;reg_address<=regno;write_value<=val;read_count<=n;after_transaction<=next_state;state<=17;end endtask
 task fail;input[3:0]reason;begin online<=0;fault_latched<=1;failure_reason<=reason;if(first_failure_reason==0)first_failure_reason<=reason;protocol_errors<=protocol_errors+1'b1;timer<=0;state<=16;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin divider<=0;time_us<=0;time_ticks<=0;hundred<=0;end
  else if(divider==US_DIV-1)begin divider<=0;time_us<=time_us+1'b1;if(hundred==99)begin hundred<=0;time_ticks<=time_ticks+1'b1;end else hundred<=hundred+1'b1;end
  else divider<=divider+1'b1;
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;after_transaction<=0;timer<=0;address<=7'h68;alternate<=0;request<=0;read_op<=0;reg_address<=0;write_value<=0;read_count<=0;config_index<=0;
   online<=0;fault_latched<=0;reset_attempts<=0;protocol_errors<=0;sequence_gaps<=0;sensor_restarted<=0;first_failure_reason<=0;failure_reason<=0;
   fstart<=0;rax<=0;ray<=0;raz<=0;rgx<=0;rgy<=0;rgz<=0;dt_us<=5000;last_sample_us<=0;age<=0;
   quat_sequence<=0;linear_sequence<=0;quat_timestamp_ticks<=0;linear_timestamp_ticks<=0;quat_valid<=0;accel_valid<=0;gyro_valid<=0;gravity_valid<=0;linear_valid<=0;
   rate_timer<=0;rate_count<=0;pose_hz<=0;accel_hz<=0;gyro_hz<=0;received_packets<=0;received_bytes<=0;
  end else begin
   request<=0;fstart<=0;sensor_restarted<=0;quat_valid<=0;accel_valid<=0;gyro_valid<=0;gravity_valid<=0;linear_valid<=0;
   if(rate_timer==CLK_HZ-1)begin rate_timer<=0;pose_hz<=rate_count;accel_hz<=rate_count;gyro_hz<=rate_count;rate_count<=0;end else rate_timer<=rate_timer+1'b1;
   if(online && age<CLK_HZ)age<=age+1'b1;
   if(force_reset)begin state<=0;timer<=0;online<=0;fault_latched<=0;reset_attempts<=reset_attempts+1'b1;sensor_restarted<=1;alternate<=0;address<=7'h68;end
   else if(online && age>=CLK_HZ/25)fail(6);
   else case(state)
    0:if(timer>=BOOT_TICKS)begin timer<=0;state<=1;end else timer<=timer+1'b1;
    1:transaction(1,8'h75,0,1,2);
    // WHO75 is an explicit experimental compatibility allowance, not identity certification.
    2:if(data[7:0]!=8'h68 && data[7:0]!=8'h75)fail(4);else transaction(0,8'h6b,8'h80,0,3);
    3:begin timer<=0;state<=4;end
    4:if(timer>=CLK_HZ/10)begin config_index<=0;state<=5;end else timer<=timer+1'b1;
    5:transaction(0,cfg_addr(config_index),cfg_value(config_index),0,6);
    6:transaction(1,cfg_addr(config_index),0,1,7);
    7:if(data[7:0]!=cfg_value(config_index))fail(5);else if(config_index==9)begin online<=1;fault_latched<=0;sensor_restarted<=1;age<=0;timer<=0;last_sample_us<=time_us;state<=9;end else begin config_index<=config_index+1'b1;state<=5;end
    9:if(timer>=CLK_HZ/1000)begin timer<=0;state<=10;end else timer<=timer+1'b1;
    10:transaction(1,8'h3a,0,1,11);
    11:if(data[0])state<=12;else state<=9;
    12:transaction(1,8'h3b,0,14,13);
    13:begin
     rax<={data[7:0],data[15:8]};ray<={data[23:16],data[31:24]};raz<={data[39:32],data[47:40]};
     rgx<={data[71:64],data[79:72]};rgy<={data[87:80],data[95:88]};rgz<={data[103:96],data[111:104]};
     dt_us<=time_us-last_sample_us>10000 ? 16'd10000 : time_us-last_sample_us;last_sample_us<=time_us;state<=14;
    end
    14:begin fstart<=1;state<=15;end
    15:if(fb_done)begin
     age<=0;state<=9;rate_count<=rate_count+1'b1;
     received_packets<=received_packets+1'b1;received_bytes<=received_bytes+16'd14;
     quat_sequence<=quat_sequence+1'b1;linear_sequence<=linear_sequence+1'b1;
     // Board read/fusion completion timestamp, NOT exact sensor sampling time.
     quat_timestamp_ticks<=time_ticks;linear_timestamp_ticks<=time_ticks;
     accel_valid<=1;gyro_valid<=1;gravity_valid<=1;
     quat_valid<=!REPORT_BACKPRESSURE || quat_ready;linear_valid<=!REPORT_BACKPRESSURE || linear_ready;
     if(REPORT_BACKPRESSURE && (!quat_ready || !linear_ready))sequence_gaps<=sequence_gaps+1'b1;
    end
    16:if(timer>=CLK_HZ)begin timer<=0;state<=0;fault_latched<=0;reset_attempts<=reset_attempts+1'b1;sensor_restarted<=1;end else timer<=timer+1'b1;
    17:if(done)begin
     if(error!=0)begin
      if(after_transaction==2 && !alternate)begin alternate<=1;address<=7'h69;state<=1;end
      else fail(2);
     end else state<=after_transaction;
    end
    default:state<=0;
   endcase
  end
 end
endmodule
