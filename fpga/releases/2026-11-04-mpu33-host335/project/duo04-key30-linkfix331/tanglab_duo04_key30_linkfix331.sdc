# Raw 50 MHz reference reaches PLL only. Core=50, pixel=49, serializer=245 MHz.
create_clock -name ref_clk -period 20.000 [get_ports {clk}]
# Gowin derives PLL clocks from the PLL primitive parameters. Do not create
# unrelated base clocks at its outputs: that would hide real relationships.
# First-stage handshake synchronizers only; held snapshot bus remains timed.
set_false_path -to [get_regs {display/status_cdc/request_sync_0*}]
set_false_path -to [get_regs {display/status_cdc/ack_sync_0*}]
# No broad false-path on pixel_status or PLL-derived data paths.

# Only the first D in the pixel-domain reset synchronizer crosses domains.
set_false_path -to [get_regs {display/pixel_reset_pipe_0*}]
