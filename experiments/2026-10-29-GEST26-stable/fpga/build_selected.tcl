# UI23 selected route2; validated independently against route1.
set root [file dirname [file normalize [info script]]]
cd $root
open_project tanglab_duo04_stable26.gprj
set_option -top_module top_duo04
set_option -route_option 2
set_option -timing_driven 1
run all
exit 0
