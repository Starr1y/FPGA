set root [file dirname [file normalize [info script]]]
cd $root
open_project tanglab_duo04_ui23.gprj
set_option -top_module top_duo04
set_option -route_option 2
set_option -timing_driven 1
run pnr
exit 0
