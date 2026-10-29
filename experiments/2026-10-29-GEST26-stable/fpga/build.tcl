set root [file dirname [file normalize [info script]]]
cd $root
open_project tanglab_duo04_stable26.gprj
set_option -top_module top_duo04
# SUG100 printed p39: GW5A(S)(T)-138 defaults to fast route algorithm 2.
set_option -route_option 1
set_option -timing_driven 1
run all
