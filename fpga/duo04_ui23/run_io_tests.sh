#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p validation
for test in serial_formats mixed_latency audio_latency fan04_expression_200; do
  iverilog -g2012 -DTANG_SIM -s "tb_$test" -o "validation/$test.vvp" tb/*.sv rtl/*.v > "validation/$test.compile.log" 2>&1
  vvp "validation/$test.vvp" > "validation/$test.log" 2>&1
  grep TB_PASS "validation/$test.log"
done
