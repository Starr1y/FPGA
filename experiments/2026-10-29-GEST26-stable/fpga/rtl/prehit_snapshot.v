// Sensor timestamps are 100us ticks. Serial search avoids a 32-way priority mux.
// Store only new, valid pose reports; never manufacture history from wall time.
module prehit_snapshot(
 input clk,rst_n,clear,pose_valid,pose_ok,
 input [31:0] pose_tick,input [3:0] zone,input [1:0] octave,profile,
 input request,input [31:0] event_tick,
 output reg busy,done,valid,
 output reg [3:0] selected_zone,output reg [1:0] selected_octave,selected_profile,
 output reg [31:0] selected_tick,output reg [31:0] overruns
);
 reg [31:0] stamps[0:31];reg [7:0] values[0:31];reg [31:0] occupied;
 reg [4:0] wr,index;reg [31:0] event_q,best_age,last_pose;reg have_pose;
 wire [31:0] age=event_q-stamps[index];
 always @(posedge clk)begin
  if(!rst_n)begin
   busy<=0;done<=0;valid<=0;selected_zone<=0;selected_octave<=0;selected_profile<=0;
   selected_tick<=0;overruns<=0;occupied<=0;wr<=0;index<=0;event_q<=0;best_age<=32'hffffffff;last_pose<=0;have_pose<=0;
  end else begin
   done<=0;
   if(pose_valid && pose_ok && (!have_pose || ($signed(pose_tick-last_pose)>0)))begin
    stamps[wr]<=pose_tick;values[wr]<={profile,octave,zone};occupied[wr]<=1;wr<=wr+1'b1;last_pose<=pose_tick;have_pose<=1;
   end
   if(request)begin
    if(busy)overruns<=overruns+1'b1;
    else begin busy<=1;index<=0;event_q<=event_tick;best_age<=32'hffffffff;valid<=0;end
   end
   if(busy)begin
    if(occupied[index] && age>=300 && age<=800 && age<best_age)begin
     best_age<=age;selected_tick<=stamps[index];
     {selected_profile,selected_octave,selected_zone}<=values[index];valid<=1;
    end
    if(index==31)begin busy<=0;done<=1;end else index<=index+1'b1;
   end
   if(clear)begin occupied<=0;wr<=0;have_pose<=0;busy<=0;done<=0;valid<=0;end
  end
 end
endmodule
