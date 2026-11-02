// WHO75 is accepted only in an explicitly enabled diagnostic experiment.
// Direct MPU6050 acquisition. No synthesized orientation or fake accuracy.
// +/-4g (8192LSB/g), +/-500deg/s (65.5LSB/(deg/s)), DLPF3,200Hz.
module mpu6050_raw_host #(parameter CLK_HZ=50000000,HALF_DIV=100,ALLOW_WHO75_DIAG=0)(
 input clk,rst_n,force_reset,scl_in,sda_in,int_in,
 output[3:0]debug_state,debug_index,output[7:0]debug_register,debug_read,
 output[31:0]timestamp_now,output scl_low,sda_low,output reg configured,online,sample_valid,
 output reg signed[15:0]ax,ay,az,temperature,gx,gy,gz,
 output reg[31:0]sample_tick,errors,samples,output reg[3:0]last_error
);
 reg[1:0]int_sync;reg int_old,pending;reg[31:0]int_tick,pending_tick;
 reg[31:0]divider,ticks,timer,age;reg[3:0]state,config_index;

 reg start,read;reg[7:0]reg_addr,value;reg[4:0]length;
 wire busy,done;wire[3:0]failure;wire[119:0]bytes;
 wire req,edone,eack;wire[2:0]cmd;wire[7:0]wd,rd;wire[3:0]ee;
 wire local_reset=rst_n && !force_reset;
 assign timestamp_now=ticks;assign debug_state=state;assign debug_index=config_index;assign debug_register=reg_addr;assign debug_read=bytes[7:0];
 mpu_register_transaction transaction(.clk(clk),.rst_n(local_reset),.start(start),.read(read),.device_address(7'h68),.register_address(reg_addr),.write_value(value),.read_count(length),.busy(busy),.done(done),.failure(failure),.read_bytes(bytes),.request(req),.command(cmd),.write_data(wd),.engine_done(edone),.engine_ack(eack),.engine_error(ee),.engine_data(rd));
 mpu_byte_master #(.HOLD_DIV((CLK_HZ/2000000)>0 ? CLK_HZ/2000000 : 1),.HALF_DIV(HALF_DIV),.TIMEOUT(CLK_HZ/40)) bus(.clk(clk),.rst_n(local_reset),.request(req),.command(cmd),.write_data(wd),.scl_in(scl_in),.sda_in(sda_in),.scl_low(scl_low),.sda_low(sda_low),.busy(),.done(edone),.ack(eack),.read_data(rd),.error(ee));
 function[7:0]cfg_register;input[3:0]i;begin case(i)0:cfg_register=8'h6b;1:cfg_register=8'h19;2:cfg_register=8'h1a;3:cfg_register=8'h1b;4:cfg_register=8'h1c;5:cfg_register=8'h37;default:cfg_register=8'h38;endcase end endfunction
 function[7:0]cfg_value;input[3:0]i;begin case(i)0:cfg_value=1;1:cfg_value=4;2:cfg_value=3;3,4:cfg_value=8;5:cfg_value=8'h20;default:cfg_value=1;endcase end endfunction
 function signed[15:0]be16;input[4:0]offset;begin be16={bytes[offset*8+:8],bytes[(offset+1)*8+:8]};end endfunction
 always @(posedge clk)begin
  if(!local_reset)begin
   int_sync<=0;int_old<=0;pending<=0;int_tick<=0;pending_tick<=0;divider<=0;ticks<=0;timer<=0;age<=0;state<=0;config_index<=0;start<=0;read<=0;reg_addr<=0;value<=0;length<=1;configured<=0;online<=0;sample_valid<=0;sample_tick<=0;errors<=0;samples<=0;last_error<=0;ax<=0;ay<=0;az<=0;temperature<=0;gx<=0;gy<=0;gz<=0;
  end else begin
   int_sync<={int_sync[0],int_in};int_old<=int_sync[1];start<=0;sample_valid<=0;
   if(divider==CLK_HZ/10000-1)begin divider<=0;ticks<=ticks+1'b1;end else divider<=divider+1'b1;
   if(timer!=0)timer<=timer-1'b1;
   if(age<CLK_HZ)age<=age+1'b1;
   if(int_sync[1] && !int_old)begin pending<=1;int_tick<=ticks;end
   case(state)
    0:begin configured<=0;online<=0;pending<=0;timer<=CLK_HZ/10;state<=1;end
    1:if(timer==0)begin reg_addr<=8'h75;read<=1;length<=1;start<=1;state<=2;end
    2:if(done)begin
     if(failure!=0 || (bytes[7:0]!=8'h68 && !(ALLOW_WHO75_DIAG && bytes[7:0]==8'h75)))begin last_error<=failure!=0 ? failure : 2;errors<=errors+1'b1;state<=0;end
     else begin reg_addr<=8'h6b;value<=8'h80;read<=0;start<=1;state<=3;end
    end
    3:if(done)begin
     if(failure!=0)begin last_error<=failure;errors<=errors+1'b1;state<=0;end
     else begin timer<=CLK_HZ/10;state<=4;config_index<=0;end
    end
    4:if(timer==0)begin reg_addr<=cfg_register(config_index);value<=cfg_value(config_index);read<=0;start<=1;state<=5;end
    5:if(done)begin
     if(failure!=0)begin last_error<=failure;errors<=errors+1'b1;state<=0;end
     else begin read<=1;length<=1;start<=1;state<=6;end
    end
    6:if(done)begin
     if(failure!=0 || bytes[7:0]!=cfg_value(config_index))begin last_error<=failure!=0 ? failure : 3;errors<=errors+1'b1;state<=0;end
     else if(config_index==6)begin
      // INT may already be latched while reading back INT_ENABLE. Drain a
      // complete first report without publishing an unknown-age sample.
      configured<=1;age<=0;pending<=0;reg_addr<=8'h3a;read<=1;length<=15;start<=1;state<=9;
     end
     else begin config_index<=config_index+1'b1;state<=4;end
    end
    7:if(pending)begin
     pending<=0;pending_tick<=int_tick;reg_addr<=8'h3a;read<=1;length<=15;start<=1;state<=8;
    end
    8:if(done)begin
     if(failure!=0 || !bytes[0] || ticks-pending_tick>40)begin last_error<=failure!=0 ? failure : ticks-pending_tick>40 ? 6 : 4;errors<=errors+1'b1;state<=0;end
     else begin sample_tick<=pending_tick;ax<=be16(1);ay<=be16(3);az<=be16(5);temperature<=be16(7);gx<=be16(9);gy<=be16(11);gz<=be16(13);sample_valid<=1;age<=0;online<=1;samples<=samples+1'b1;last_error<=0;state<=7;end
    end
    9:if(done)begin
     if(failure!=0)begin last_error<=failure;errors<=errors+1'b1;configured<=0;state<=0;end
     else state<=7;
    end
    default:state<=0;
   endcase
   // Never keep old orientation eligible when INT or report delivery stops.
   if(configured && age>=CLK_HZ/20)begin online<=0;configured<=0;sample_valid<=0;errors<=errors+1'b1;last_error<=5;state<=0;end
  end
 end
endmodule


