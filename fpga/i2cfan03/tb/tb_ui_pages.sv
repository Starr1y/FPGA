`timescale 1ns/1ps
module tb_ui_pages;
 reg clk=0;always #20 clk=!clk;
 reg rst_n=0,status_update=0;reg [1023:0] performance_status=0;
 wire [7:0] red,green,blue;
 video_instrument_panel dut(.clk(clk),.rst_n(rst_n),.levels(40'd0),.mix_sample(8'd0),.sample_update(1'b0),
  .performance_status(performance_status),.status_update(status_update),.red(red),.green(green),.blue(blue));
 task publish;begin status_update=1;@(negedge clk);status_update=0;repeat(300)@(negedge clk);end endtask
 task probe(input integer xx,yy);begin force dut.x=xx;force dut.y=yy;repeat(2)@(negedge clk);#1;end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  performance_status[969]=1;performance_status[6]=1;performance_status[3:0]=7;performance_status[249:247]=3;
  performance_status[242:240]=2;performance_status[1008:1005]=2;performance_status[1021]=1;publish();
  if(dut.diagnostic_view)$fatal(1,"default is not performance page");
  probe(48,178);if(dut.label_id==21)$fatal(1,"pose text visible on primary page");
  probe(382,198);if(dut.text_len!=0)$fatal(1,"ERR/RST text visible on primary page");
  probe(48,112);if(dut.label_id!=14)$fatal(1,"ready state hidden");
  // Changing upstream status must not tear a displayed frame.
  performance_status[1003]=1;#1;if(dut.diagnostic_view)$fatal(1,"unsnapshotted page switch");
  publish();if(!dut.diagnostic_view)$fatal(1,"page snapshot lost");
  probe(48,178);if(dut.label_id!=21 || dut.text_len!=2)$fatal(1,"yaw diagnostics missing");
  probe(382,198);if(dut.text_len!=17)$fatal(1,"communication diagnostics missing");
  performance_status[1003]=0;performance_status[249:247]=5;performance_status[6]=0;publish();
  probe(48,112);if(dut.label_id!=20)$fatal(1,"fault state hidden in primary view");
  performance_status[249:247]=3;performance_status[6]=1;performance_status[3:0]=5;publish();
  probe(48,112);if(dut.label_id!=12)$fatal(1,"range protection status hidden");
  performance_status[3:0]=3;publish();probe(48,112);if(dut.label_id!=10)$fatal(1,"low quality state hidden");
  performance_status[1004]=1;publish();probe(90,60);if(dut.label_id!=47)$fatal(1,"long-press release hint missing");
  // Selected preview and actual accepted-hit feedback remain independent.
  performance_status[324]=1;performance_status[3:0]=7;performance_status[5:4]=3;performance_status[9]=1;performance_status[7]=1;performance_status[14]=1;publish();probe(364,300);if({red,green,blue}!=24'hFF006E)$fatal(1,"actual hit tile missing");
  probe(276,300);if({red,green,blue}!=24'h0C3A45)$fatal(1,"preview highlight lost");
  $display("TB_PASS primary diagnostics hidden, actionable states retained, atomic page snapshots, independent hit and preview");$finish;
 end
 initial begin #500000;$fatal(1,"page watchdog");end
endmodule
