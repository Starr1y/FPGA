# Standalone resource/inference check only. No board pins, place/route or bitstream.
open_project stereo_fx.gprj
set_option -top_module stereo_fx
run syn
