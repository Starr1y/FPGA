#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p validation
for name in tb_lesson_event_pipeline tb_scheduler_predecode; do
  iverilog -g2012 -DTANG_SIM -s "$name" -o "validation/$name.vvp" "tb/$name.sv" tb/reference/*.v rtl/*.v > "validation/$name.compile.log" 2>&1
  vvp "validation/$name.vvp" > "validation/$name.log" 2>&1
  grep TB_PASS "validation/$name.log"
done
