#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash run_regressions.sh
bash run_io_tests.sh
