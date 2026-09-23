// BNO085 transport only. Report decoding and feature requests are on the PC.
module imu_transport #(parameter CLK_HZ=50000000)(
 input clk,input rst_n,input [31:0] ticks,input mode_valid,input [1:0] mode_in,
 input tx_request,input [6:0] tx_length,input [511:0] tx_payload,output tx_busy,
 input imu_data,input imu_int_n,output imu_clk_tx,output reg imu_cs_n,
 output reg imu_mosi,output reg imu_rst_n,output reg imu_wake,
 output reg packet_ready,input packet_take,output reg [9:0] packet_length,
 input [9:0] read_addr,output [7:0] read_data,output reg [31:0] stamp_start,stamp_end,stamp_parsed,
 output reg [31:0] drops,output reg [1:0] mode);
 reg [7:0] buffer[0:511];assign read_data=buffer[read_addr[8:0]];
 reg [1:0] ints;reg last_int;reg [31:0] int_stamp;
 reg [25:0] reset_count;reg [31:0] idle_count;
 wire [7:0] rx_data;wire rx_valid,rx_start,rx_error;
 wire [31:0] baud=mode==0?115200:3000000;
 uart_rx #(.CLK_HZ(CLK_HZ)) ur(clk,rst_n && imu_rst_n,imu_data,baud,rx_data,rx_valid,rx_start,rx_error);
 reg [9:0] pos;reg uart_active;reg [31:0] uart_start;
 reg [511:0] txbuf;reg [6:0] txlen,txpos;reg txactive;
 reg [31:0] spacing;wire uart_ready,uart_tx_pin;
 wire uart_send=txactive && mode==1 && spacing==0;
 uart_tx #(.CLK_HZ(CLK_HZ)) ut(clk,rst_n,32'd3000000,txbuf[txpos*8+:8],uart_send,uart_ready,uart_tx_pin);
 assign tx_busy=txactive || reset_count!=0;
 reg sck;reg [5:0] spi_state;reg [7:0] spi_rx,spi_tx;reg [3:0] bitcount;
 reg [15:0] divider;reg [15:0] spi_length;reg spi_write;reg [31:0] spi_timeout;
 assign imu_clk_tx=mode==2?sck:uart_tx_pin;
 always @(posedge clk)begin
  if(!rst_n)begin
   ints<=3;last_int<=1;int_stamp<=0;reset_count<=CLK_HZ/100;imu_rst_n<=0;imu_wake<=1;mode<=0;
   packet_ready<=0;packet_length<=0;pos<=0;uart_active<=0;uart_start<=0;idle_count<=0;drops<=0;
   txactive<=0;txbuf<=0;txlen<=0;txpos<=0;spacing<=0;
   sck<=1;imu_cs_n<=1;imu_mosi<=0;spi_state<=0;divider<=0;spi_rx<=0;spi_tx<=0;bitcount<=0;spi_length<=0;spi_write<=0;spi_timeout<=0;
   stamp_start<=0;stamp_end<=0;stamp_parsed<=0;
  end else begin
   ints<={ints[0],imu_int_n};last_int<=ints[1];
   if(last_int && !ints[1])int_stamp<=ticks;
   if(packet_take)packet_ready<=0;
   if(mode_valid)begin
    mode<=mode_in;reset_count<=CLK_HZ/100;imu_rst_n<=0;imu_wake<=1;pos<=0;uart_active<=0;packet_ready<=0;txactive<=0;spi_state<=0;imu_cs_n<=1;sck<=1;
   end else if(reset_count!=0)begin
    reset_count<=reset_count-1;
    if(reset_count==1)begin imu_rst_n<=1;idle_count<=0;end
   end else begin
    if(tx_request && !txactive && tx_length!=0)begin txbuf<=tx_payload;txlen<=tx_length;txpos<=0;txactive<=1;spacing<=CLK_HZ/500;end
    if(spacing!=0)spacing<=spacing-1;
    if(uart_send && uart_ready)begin
     spacing<=CLK_HZ/500;
     if(txpos+1==txlen)txactive<=0;else txpos<=txpos+1;
    end
    if(mode!=2)begin
     if(rx_error)begin drops<=drops+1;uart_active<=0;pos<=0;end
     if(rx_start && !uart_active)uart_start<=ticks;
     if(uart_active)begin
      if(idle_count>=CLK_HZ/20)begin uart_active<=0;pos<=0;drops<=drops+1;end
      else idle_count<=idle_count+1;
     end
     if(rx_valid)begin
      idle_count<=0;
      if(packet_ready)begin uart_active<=0;pos<=0;if(mode==0 && rx_data==8'haa) drops<=drops+1;else if(mode==1 && rx_data==8'h7e)drops<=drops+1;end
      else if(mode==0)begin
       if(!uart_active)begin
        if(rx_data==8'haa)begin buffer[0]<=rx_data;pos<=1;uart_active<=1;stamp_start<=uart_start;end
       end else if(pos==1 && rx_data!=8'haa)begin uart_active<=0;pos<=0;end
       else begin
        buffer[pos]<=rx_data;
        if(pos==18)begin packet_ready<=1;packet_length<=19;stamp_end<=ticks;stamp_parsed<=ticks+1;pos<=0;uart_active<=0;end
        else pos<=pos+1;
       end
      end else begin
       if(rx_data==8'h7e)begin
        if(uart_active && pos>1)begin buffer[pos]<=rx_data;packet_ready<=1;packet_length<=pos+1;stamp_end<=ticks;stamp_parsed<=ticks+1;uart_active<=0;pos<=0;end
        else begin buffer[0]<=rx_data;pos<=1;uart_active<=1;stamp_start<=ints[1]?uart_start:int_stamp;end
       end else if(uart_active)begin
        if(pos<511)begin buffer[pos]<=rx_data;pos<=pos+1;end
        else begin uart_active<=0;pos<=0;drops<=drops+1;end
       end
      end
     end
    end else begin
     case(spi_state)
      0:begin
       sck<=1;imu_cs_n<=1;imu_wake<=1;spi_timeout<=0;
       if(!packet_ready && !ints[1])begin
        spi_write<=0;spi_length<=4;pos<=0;stamp_start<=int_stamp;imu_cs_n<=0;spi_tx<=0;bitcount<=7;divider<=CLK_HZ/2000000-1;spi_state<=2;
       end else if(txactive && !packet_ready)begin imu_wake<=0;spi_state<=1;end
      end
      1:begin
       if(!ints[1])begin
        spi_write<=1;spi_length<={9'b0,txlen};pos<=0;imu_cs_n<=0;spi_tx<=txbuf[7:0];bitcount<=7;divider<=CLK_HZ/2000000-1;spi_state<=2;
       end else if(spi_timeout>=CLK_HZ/20)begin spi_state<=0;txactive<=0;drops<=drops+1;end
       else spi_timeout<=spi_timeout+1;
      end
      2:if(divider!=0)divider<=divider-1;
        else begin sck<=0;imu_mosi<=spi_tx[bitcount];divider<=CLK_HZ/2000000-1;spi_state<=3;end
      3:if(divider!=0)divider<=divider-1;
        else begin
         sck<=1;spi_rx[bitcount]<=imu_data;divider<=CLK_HZ/2000000-1;
         if(bitcount==0)spi_state<=4;else begin bitcount<=bitcount-1;spi_state<=2;end
        end
      4:begin
       if(!spi_write)buffer[pos]<=spi_rx;
       if(!spi_write && pos==1)begin
        spi_length<={spi_rx,buffer[0]};
        if(spi_rx[7] || {spi_rx,buffer[0]}<4 || {spi_rx,buffer[0]}>512)begin spi_state<=5;drops<=drops+1;end
        else begin pos<=pos+1;bitcount<=7;spi_state<=2;end
       end else if(pos+1>=spi_length)begin
        if(!spi_write)begin packet_length<=spi_length[9:0];packet_ready<=1;stamp_end<=ticks;stamp_parsed<=ticks+1;end
        else txactive<=0;
        spi_state<=5;
       end else begin pos<=pos+1;bitcount<=7;spi_state<=2;if(spi_write)spi_tx<=txbuf[(pos+1)*8+:8];end
      end
      5:if(divider!=0)divider<=divider-1;else begin imu_cs_n<=1;imu_wake<=1;spi_state<=0;end
      default:spi_state<=0;
     endcase
    end
   end
  end
 end
endmodule
