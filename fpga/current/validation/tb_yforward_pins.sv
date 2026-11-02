`timescale 1ns/1ps
// Pin-level open-drain slave model for the exact MPU subset used by host.
module tb_yforward_pins;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;tri1 scl,sda;wire scl_low,sda_low;
 reg slave_sda=0,slave_scl=0,interrupt=0,enable_samples=1,stretch=0;
 assign scl=scl_low||slave_scl ? 1'b0 : 1'bz;
 assign sda=sda_low||slave_sda ? 1'b0 : 1'bz;
 wire configured,online,valid;wire signed[15:0]ax,ay,az,temp,gx,gy,gz;
 wire[31:0]stamp,now_tick,errors;wire[3:0]failure;
 reg calibrate=0,button_n=1;wire[255:0]status;integer hits=0;
 bno_i2c_hand #(.DIRECT_MPU(1),.BUTTON_TRIGGER(1),.CLK_HZ(1000000)) d(.clk(clk),.rst_n(rst_n),.enabled(1'b1),.force_reset(1'b0),.calibrate(calibrate),.express(1'b0),.mirror(1'b0),.button_n(button_n),.layout_profile(2'd0),.scl_in(scl),.sda_in(sda),.int_n(interrupt),.snapshot_enable(1'b0),.stable_octave(2'd0),.scl_low(scl_low),.sda_low(sda_low),.online(online),.status(status),.note_on());
 defparam d.mpu_source.host.HALF_DIV=2; // Preserve250kHz at the1MHz simulation clock.
 assign configured=d.mpu_source.raw_configured;assign valid=d.mpu_source.raw_valid;
 assign ax=d.mpu_source.raw_ax;assign ay=d.mpu_source.raw_ay;assign az=d.mpu_source.raw_az;
 assign temp=d.mpu_source.temperature;assign gx=d.mpu_source.raw_gx;assign gy=d.mpu_source.raw_gy;assign gz=d.mpu_source.raw_gz;
 assign stamp=d.mpu_source.raw_stamp;assign now_tick=d.report_clock;assign errors=d.mpu_source.host_errors;assign failure=d.mpu_source.host_failure;
 always @(posedge clk)if(d.note_on)hits=hits+1;

 reg[7:0]registers[0:127];reg[7:0]shift=0,tx=0,pointer=0;
 integer state=0,bit_index=7,stretch_count=0,sample_div=0,received=0,starts=0,stops=0,nacks=0,acks=0;
 reg active=0,address_phase=1,pointer_phase=1,reading=0,selected=0;
 localparam RX=0,ACK_PRE=1,ACK_ACTIVE=2,POST_ACK=3,TX=4,MASTER_ACK_PRE=5,MASTER_ACK_ACTIVE=6,TX_NEXT=7,IDLE=8;
 function[7:0]value_at;input[7:0]a;begin value_at=a==8'h3a ? {7'd0,interrupt} : registers[a];end endfunction
 task load_tx;begin tx=value_at(pointer);slave_sda=!tx[7];bit_index=7;state=TX;if(pointer==8'h3a)interrupt=0;end endtask
 always @(negedge sda)if(scl===1'b1 && rst_n)begin
  active=1;address_phase=1;pointer_phase=1;selected=0;reading=0;state=RX;bit_index=7;shift=0;starts=starts+1;
 end
 always @(posedge sda)if(scl===1'b1 && rst_n)begin active=0;state=IDLE;slave_sda=0;stops=stops+1;end
 always @(posedge scl)if(active)begin
  case(state)
   RX:begin
    shift[bit_index]=sda;
    if(bit_index==0)begin
     if(address_phase)begin selected=shift[7:1]==7'h68;reading=shift[0];address_phase=0;end
     else if(pointer_phase)begin pointer=shift;pointer_phase=0;end
     else begin registers[pointer]=shift;
      if(pointer==8'h6b && shift==8'h80)begin registers[8'h38]=0;interrupt=0;end
      if(pointer==8'h38 && shift==1)sample_div=4999;
      pointer=pointer+1'b1;end
     state=ACK_PRE;
    end else bit_index=bit_index-1;
   end
   ACK_ACTIVE:state=POST_ACK;
   TX:if(bit_index==0)state=MASTER_ACK_PRE;else bit_index=bit_index-1;
   MASTER_ACK_ACTIVE:if(sda===1'b0)begin acks=acks+1;state=TX_NEXT;end else begin nacks=nacks+1;state=IDLE;end
   default:begin end
  endcase
 end
 always @(negedge scl)if(active)begin
  case(state)
   ACK_PRE:begin slave_sda=selected;state=ACK_ACTIVE;if(stretch)begin slave_scl=1;stretch_count=8;end end
   POST_ACK:begin slave_sda=0;bit_index=7;shift=0;if(reading)load_tx();else state=RX;end
   TX:slave_sda=!tx[bit_index];
   MASTER_ACK_PRE:begin slave_sda=0;state=MASTER_ACK_ACTIVE;end
   TX_NEXT:begin pointer=pointer+1'b1;load_tx();end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(stretch_count>0)stretch_count=stretch_count-1;else slave_scl=0;
  if(registers[8'h38][0] && enable_samples)begin
   if(sample_div==4999)begin sample_div=0;interrupt=1;end else sample_div=sample_div+1;
  end
  if(valid)begin
   received=received+1;if(received%100==0)begin $display("PROGRESS samples%0d tick%0d flags%h bias%0d fusionstate%0d",received,now_tick,status[31:0],d.mpu_source.fusion.calibration_samples,d.mpu_source.fusion.state);$fflush();end
   if(ax!=8192 || ay!=0 || az!=0 || temp!=333 || gx!=$signed({registers[8'h43],registers[8'h44]}) || gy!=-13 || gz!=$signed({registers[8'h47],registers[8'h48]}))$fatal(1,"pin-level burst endian/sign error");
   if(now_tick-stamp>40)$fatal(1,"late physical burst published");
  end
 end
 integer i;
 initial begin
  for(i=0;i<128;i=i+1)registers[i]=0;
  registers[8'h75]=8'h75;
  registers[8'h3b]=8'h20;registers[8'h3c]=0;
  registers[8'h3d]=0;registers[8'h3e]=0;
  registers[8'h3f]=0;registers[8'h40]=0;
  registers[8'h41]=8'h01;registers[8'h42]=8'h4d;
  registers[8'h43]=0;registers[8'h44]=31;
  registers[8'h45]=8'hff;registers[8'h46]=8'hf3;
  registers[8'h47]=0;registers[8'h48]=31;
  repeat(5)@(negedge clk);rst_n=1;
  wait(received==10);stretch=1;
  wait(received>=420);@(negedge clk);calibrate=1;repeat(50)@(negedge clk);calibrate=0;
  wait(status[1] && status[4]);@(negedge clk);
  if(status[21:18]!=3 || $signed(status[47:32])>16 || $signed(status[47:32])< -16)$fatal(1,"pin-level center error");
  registers[8'h43]=8'h07;registers[8'h44]=8'hcc; //1996=31bias+1965=30deg/s
  sample_div=0;received=0;wait(received>=300);
  registers[8'h43]=0;registers[8'h44]=31;
  received=0;wait(received>=20);@(negedge clk);
  if(status[21:18]!=5 || hits!=0)$fatal(1,"pin-level yaw selection zone%0d hits%0d",status[21:18],hits);
  button_n=0;received=0;wait(received>=10);if(hits!=1)$fatal(1,"pin-level button missing");
  received=0;wait(received>=20);if(hits!=1)$fatal(1,"pin-level button repeated");
  enable_samples=0;
  repeat(60000)@(negedge clk);
  if(online || errors==0 || failure!=5)$fatal(1,"missing physical INT not detected");
  if(nacks<15 || acks<15*14 || starts<30 || stops<30)$fatal(1,"ACK/NACK or transaction coverage");
  $display("TB_PASS full pin-level MPU->raw->fusion->relative origin->45degree selection->button;clockstretch,hold,missingINT;starts%0d stops%0d ACK%0d NACK%0d",starts,stops,acks,nacks);$finish;
 end
 initial begin #100000000;$fatal(1,"pin test timeout configured%0d errors%0d failure%0d state%0d",configured,errors,failure,d.mpu_source.host.state);end
endmodule
