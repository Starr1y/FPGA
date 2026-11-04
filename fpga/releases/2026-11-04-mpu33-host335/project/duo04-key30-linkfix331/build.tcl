set root [file dirname [file normalize [info script]]]
cd $root
open_project tanglab_duo04_key30_linkfix331.gprj
set_option -top_module top_duo04
# Structural repair: default device fast router; timing/hold constraints unchanged.
set_option -route_option 2
set_option -timing_driven 1
run all
