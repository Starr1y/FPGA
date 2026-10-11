// Iterative fixed-point primitives keep arithmetic out of a long pixel path.
// Angle output: signed degrees * 16 (Q4). atan2 uses 16 CORDIC steps.
module pose_atan2(
    input clk,input rst_n,input start,input signed [31:0] vx,vy,
    output reg busy,output reg valid,output reg signed [15:0] angle
);
    reg signed [31:0] x,y;
    reg signed [23:0] z;
    reg [4:0] step;
    reg signed [31:0] nx,ny;
    reg signed [23:0] nz;
    function signed [23:0] turn;
        input [4:0] index;
        begin case(index)
            0:turn=184320;1:turn=108810;2:turn=57492;3:turn=29184;
            4:turn=14649;5:turn=7331;6:turn=3667;7:turn=1833;
            8:turn=917;9:turn=458;10:turn=229;11:turn=115;
            12:turn=57;13:turn=29;14:turn=14;15:turn=7;
            default:turn=0;
        endcase end
    endfunction
    always @* begin
        if(y>=0) begin nx=x+(y>>>step);ny=y-(x>>>step);nz=z+turn(step);end
        else begin nx=x-(y>>>step);ny=y+(x>>>step);nz=z-turn(step);end
    end
    always @(posedge clk) begin
        if(!rst_n) begin x<=0;y<=0;z<=0;step<=0;busy<=0;valid<=0;angle<=0;end
        else begin
            valid<=0;
            if(start && !busy) begin
                // Extra fractional coordinate bits preserve small-angle accuracy.
                if(vx<0) begin x<=-vx<<<8;y<=-vy<<<8;z<=vy<0 ? -737280 : 737280;end
                else begin x<=vx<<<8;y<=vy<<<8;z<=0;end
                step<=0;busy<=1;
                if(vx==0 && vy==0) begin angle<=0;valid<=1;busy<=0;end
            end else if(busy) begin
                x<=nx;y<=ny;z<=nz;
                if(step==15) begin angle<=nz>>>8;valid<=1;busy<=0;end
                else step<=step+1'b1;
            end
        end
    end
endmodule

module pose_isqrt(
    input clk,input rst_n,input start,input [31:0] radicand,
    output reg busy,output reg valid,output reg [15:0] result
);
    reg [31:0] rad;
    reg [33:0] remainder;
    reg [15:0] root;
    reg [4:0] step;
    wire [33:0] next_remainder=(remainder<<2)|rad[31:30];
    wire [33:0] trial=({18'b0,root}<<2)|1;
    wire accepted=next_remainder>=trial;
    wire [15:0] next_root=(root<<1)|accepted;
    always @(posedge clk) begin
        if(!rst_n) begin rad<=0;remainder<=0;root<=0;step<=0;busy<=0;valid<=0;result<=0;end
        else begin
            valid<=0;
            if(start && !busy) begin rad<=radicand;remainder<=0;root<=0;step<=0;busy<=1;end
            else if(busy) begin
                remainder<=accepted ? next_remainder-trial : next_remainder;
                root<=next_root;rad<=rad<<2;
                if(step==15) begin result<=next_root;busy<=0;valid<=1;end
                else step<=step+1'b1;
            end
        end
    end
endmodule
