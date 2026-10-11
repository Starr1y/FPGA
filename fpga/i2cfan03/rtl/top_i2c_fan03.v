module top_i2c_fan03(input clk,input reset_key,input key0_n,input key1_n,input key2_n,input pc_rx,output pc_tx,
 inout imu_data,input imu_int_n,input imu_power_good,inout imu_clk_tx,output imu_cs_n,output imu_mosi,output imu_rst_n,output imu_wake,
 output hp_bck,output hp_ws,output hp_din,output pa_en,output event_mark,output audio_mark,
 output tmds_clk_p_0,output tmds_clk_n_0,
 output [2:0] tmds_d_p_0,output [2:0] tmds_d_n_0);
 top #(.BENCH_MANUAL(1),.AUTONOMOUS_SPI(1),.UI_ONLY(1)) core(.clk(clk),.reset_key(reset_key),.key0_n(key0_n),.key1_n(key1_n),.key2_n(key2_n),.pc_rx(pc_rx),.pc_tx(pc_tx),.imu_data(imu_data),.imu_int_n(imu_int_n),.imu_power_good(imu_power_good),.imu_clk_tx(imu_clk_tx),.imu_cs_n(imu_cs_n),.imu_mosi(imu_mosi),.imu_rst_n(imu_rst_n),.imu_wake(imu_wake),.hp_bck(hp_bck),.hp_ws(hp_ws),.hp_din(hp_din),.pa_en(pa_en),.event_mark(event_mark),.audio_mark(audio_mark),.tmds_clk_p_0(tmds_clk_p_0),.tmds_clk_n_0(tmds_clk_n_0),.tmds_d_p_0(tmds_d_p_0),.tmds_d_n_0(tmds_d_n_0));
endmodule
