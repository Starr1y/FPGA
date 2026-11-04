# Reuse local synthesis only when RTL/ROM/project inputs have not changed.
set root [file dirname [file normalize [info script]]]
cd $root
set netlist impl/gwsynthesis/tanglab_duo04_key30_linkfix331.vg
if {![file exists $netlist]} {error "No synthesis netlist; run build.tcl first"}
foreach input [concat [glob rtl/*.v] [glob rtl/*.vh] [glob rtl/*.hex] [list tanglab_duo04_key30_linkfix331.gprj]] {
    if {[file mtime $input] > [file mtime $netlist]} {
        error "Synthesis input changed: $input; run build.tcl first"
    }
}
open_project tanglab_duo04_key30_linkfix331.gprj
set_option -top_module top_duo04
set_option -route_option 2
set_option -timing_driven 1
run pnr
