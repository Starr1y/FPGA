create_clock -name sys_clk -period 20.000 [get_ports {clk}]

# Status is a held snapshot with a request/acknowledge handshake, captured
# only in vertical blank after a three-stage synchronized acknowledgement.
set_false_path -from [get_clocks {sys_clk}] -to [get_regs {display/status_cdc/pixel_status_*}]
set_false_path -from [get_clocks {sys_clk}] -to [get_regs {display/status_cdc/ack_sync_0*}]
# Only the first core-domain stage receives the asynchronous pixel request.
set_false_path -to [get_regs {display/status_cdc/request_sync_0*}]
# The pixel reset pipe asynchronously asserts reset from sys_clk/PLL lock and
# releases it on pixel_clk. Only the async reset pins cross this boundary.
set_false_path -from [get_clocks {sys_clk}] -to [get_regs {display/pixel_reset_pipe_*}]
# UI_ONLY=1 removes the audio display CDC registers. Audio-profile exceptions
# are preserved in tanglab_audio.sdc for a future UI_ONLY=0 build.
