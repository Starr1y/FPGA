set root [file dirname [file normalize [info script]]]
cd $root
open_project tanglab_duo04_io22.gprj
set_option -top_module top_duo04
set_option -route_option 1
set_option -timing_driven 1
run all
