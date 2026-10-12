open_project tanglab_duo02.gprj
set_option -top_module top_duo02
# SUG1220-2.0E: documented routing algorithm 1; keep timing-driven routing on.
# Algorithm 2 terminated with PR0004 / zero unrouted nets on the first build.
set_option -route_option 1
set_option -timing_driven 1
run all
