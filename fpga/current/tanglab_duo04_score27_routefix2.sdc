# Raw 50 MHz reference reaches PLL only. Core=50MHz; separate video PLL pixel=49MHz, serializer=245MHz.
create_clock -name ref_clk -period 20.000 [get_ports {clk}]
# Gowin derives PLL clocks from the PLL primitive parameters. Do not create
# unrelated base clocks at its outputs: that would hide real relationships.
# First-stage handshake synchronizers only; held snapshot bus remains timed.
set_false_path -to [get_regs {display/status_cdc/request_sync_0*}]
set_false_path -to [get_regs {display/status_cdc/ack_sync_0*}]
# No broad false-path on pixel_status or PLL-derived data paths.

# Bundled snapshot settles for >=3 pixel periods before capture (61.224ns).
# Keep a20ns absolute data budget, with hold analysis; no data false path.
# Select only numeric bus FFs. Ordinary50/49/245MHz requirements remain.
set_max_delay -from [get_regs {display/status_cdc/held_status_0* display/status_cdc/held_status_1* display/status_cdc/held_status_2* display/status_cdc/held_status_3* display/status_cdc/held_status_4* display/status_cdc/held_status_5* display/status_cdc/held_status_6* display/status_cdc/held_status_7* display/status_cdc/held_status_8* display/status_cdc/held_status_9*}] -to [get_regs {display/status_cdc/pixel_status_0* display/status_cdc/pixel_status_1* display/status_cdc/pixel_status_2* display/status_cdc/pixel_status_3* display/status_cdc/pixel_status_4* display/status_cdc/pixel_status_5* display/status_cdc/pixel_status_6* display/status_cdc/pixel_status_7* display/status_cdc/pixel_status_8* display/status_cdc/pixel_status_9*}] 20.000

# Core reset crosses as one-bit data through3pixel FFs. Only its first stage is asynchronous to the core clock.
set_false_path -to [get_regs {display/pixel_reset_pipe_0*}]
report_timing -setup -max_paths 1000 -max_common_paths 1
