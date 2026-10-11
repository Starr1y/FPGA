`timescale 1ns/1ps
module tb_i2c_faults;
 reg clk=0;always #10 clk=!clk;reg rst_n=0;
 tri1 scl,sda;reg hold_scl=0,hold_sda=0;wire scl_low,sda_low;
 assign scl=(scl_low || hold_scl) ? 0 : 1'bz;assign sda=(sda_low || hold_sda) ? 0 : 1'bz;
 reg request=0;reg [2:0] command=0;reg [7:0] write_data=0;
 wire done,busy,ack;wire [7:0] read_data;wire [3:0] error;
 i2c_byte_master #(.HALF_DIV(100),.TIMEOUT(1000)) dut(.clk(clk),.rst_n(rst_n),.request(request),.command(command),.write_data(write_data),
  .scl_in(scl),.sda_in(sda),.scl_low(scl_low),.sda_low(sda_low),.done(done),.busy(busy),.ack(ack),.read_data(read_data),.error(error));
 task op(input [2:0] cmd,input [7:0] value);begin
  @(negedge clk);command=cmd;write_data=value;request=1;@(negedge clk);request=0;wait(done);@(negedge clk);
 end endtask
 real high_at,low_at;reg seen_low=0,seen_high=0;integer rises=0;
 always @(posedge scl)if(rst_n)begin high_at=$realtime;rises++;if(seen_low && $realtime-low_at<1300)$fatal(1,"SCL low time below 1.3us");seen_high=1;end
 always @(negedge scl)if(rst_n)begin low_at=$realtime;if(seen_high && $realtime-high_at<600)$fatal(1,"SCL high time below0.6us");seen_low=1;end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  op(0,0);op(2,8'h94);if(ack || error)$fatal(1,"absent slave faked ACK");op(1,0);
  if(scl!==1 || sda!==1)$fatal(1,"STOP not idle");
  hold_sda=1;op(0,0);if(error!=14 || scl_low || sda_low)$fatal(1,"stuck bus no bounded abort");hold_sda=0;
  seen_low=0;seen_high=0;
  op(0,0);hold_scl=1;op(2,8'h95);if(error!=13 || scl_low || sda_low)$fatal(1,"stretch timeout no released pads");hold_scl=0;
  rst_n=0;repeat(4)@(negedge clk);if(scl_low || sda_low)$fatal(1,"reset drives bus");
  $display("TB_PASS I2C NACK, SDA-stuck timeout, clock-stretch timeout, open-drain release/reset, datasheet high/low periods");$finish;
 end
 initial begin #1000000;$fatal(1,"byte test timeout");end
endmodule
