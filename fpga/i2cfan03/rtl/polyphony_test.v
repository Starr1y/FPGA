// Autonomous 32-frequency sine test, 125..4000 Hz. Muting changes gain, not phase or
// envelope. Stop clears every Gate and waits for rendered silence before idle.
module polyphony_test(input clk,input rst_n,input requested,input [31:0] mute_mask,
 input sample_valid,input config_ready,output reg config_valid,output reg [127:0] config_data,
 output reg busy,ready);
 reg [31:0] notes[0:31];reg [31:0] target_mask,applied_mask;
 reg [4:0] voice;reg [2:0] state;reg stopping,initializing,frames;
 initial $readmemh("rtl/test_ftw.hex",notes);
 always @(posedge clk)begin
  if(!rst_n)begin
   target_mask<=0;applied_mask<=0;voice<=0;state<=0;stopping<=0;initializing<=0;frames<=0;
   config_valid<=0;config_data<=0;busy<=0;ready<=0;
  end else begin
   case(state)
    0:if(requested)begin
     busy<=1;ready<=0;stopping<=0;initializing<=1;target_mask<=mute_mask;voice<=0;state<=1;
    end
    1:begin
     config_data<=0;config_data[7:0]<={3'b0,voice};config_data[39:8]<=notes[voice];
     config_data[47:40]<=stopping || target_mask[voice] ? 8'd0 : 8'd32;
     config_data[49:48]<=0;config_data[56]<=!stopping;config_data[58]<=initializing && !stopping;
     config_data[79:64]<=65535;config_data[95:80]<=0;
     config_data[111:96]<=65535;config_data[127:112]<=65535;
     config_valid<=1;state<=2;
    end
    2:if(config_ready)begin
     config_valid<=0;
     if(voice==31)begin frames<=0;state<=3;end
     else begin voice<=voice+1'b1;state<=1;end
    end
    3:if(sample_valid)begin
     if(!frames)frames<=1;
     else if(stopping)begin busy<=0;ready<=0;state<=0;end
     else begin applied_mask<=target_mask;ready<=1;initializing<=0;state<=4;end
    end
    4:if(mute_mask!=applied_mask)begin target_mask<=mute_mask;voice<=0;state<=1;end
   endcase
   if(!requested && busy && !stopping)begin
    stopping<=1;initializing<=0;ready<=0;voice<=0;state<=1;config_valid<=0;
   end
  end
 end
endmodule
