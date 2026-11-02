# Route2 for this independent GEST27 project; no implementation run supplied.
set root [file dirname [file normalize [info script]]]
cd $root
open_project tanglab_duo04_score27_routefix2.gprj
set_option -top_module top_duo04
set_option -verilog_std sysv2017
set_option -route_option 2
set_option -timing_driven 1
run all
exit 0
