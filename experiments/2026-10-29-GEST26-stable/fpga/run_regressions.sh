#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p validation
tests=(tb_ui21_controls tb_ui21_encoder tb_ui21_lesson tb_ui21_stop tb_ui21_panel tb_duo04_32 tb_io22_hello tb_scheduler_pipeline tb_io22_control_pipeline)
# The inherited long UART capture is optional and is not part of the recorded
# seven-test interaction gate. Enable explicitly; never count a canceled run.
if [[ "${RUN_LONG_UART:-0}" == "1" ]]; then tests+=(tb_io22_uart); fi
for name in "${tests[@]}"; do
  iverilog -g2012 -DTANG_SIM -s "$name" -o "validation/$name.vvp" "tb/$name.sv" rtl/*.v > "validation/$name.compile.log" 2>&1
  vvp "validation/$name.vvp" > "validation/$name.log" 2>&1
  grep TB_PASS "validation/$name.log"
done
