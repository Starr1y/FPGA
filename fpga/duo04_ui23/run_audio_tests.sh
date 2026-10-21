#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
for name in tb_duo04_32; do
  iverilog -g2012 -DTANG_SIM -s "$name" -o "validation/$name.vvp" "tb/$name.sv" rtl/*.v > "validation/$name.compile.log" 2>&1
  vvp "validation/$name.vvp" > "validation/$name.log" 2>&1
  grep TB_PASS "validation/$name.log"
done
