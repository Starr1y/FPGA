#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p validation preview
for name in tb_ui23_events tb_ui21_controls tb_ui21_encoder tb_ui21_lesson tb_ui21_stop; do
  iverilog -g2012 -DTANG_SIM -s "$name" -o "validation/$name.vvp" "tb/$name.sv" rtl/*.v > "validation/$name.compile.log" 2>&1
  vvp "validation/$name.vvp" > "validation/$name.log" 2>&1
  grep TB_PASS "validation/$name.log"
done
iverilog -g2012 -s tb_ui23_panel -o validation/tb_ui23_panel.vvp tb/tb_ui23_panel.sv rtl/duo04_panel.v rtl/duo_fan.v > validation/tb_ui23_panel.compile.log 2>&1
vvp validation/tb_ui23_panel.vvp > validation/tb_ui23_panel.log 2>&1
grep TB_PASS validation/tb_ui23_panel.log
