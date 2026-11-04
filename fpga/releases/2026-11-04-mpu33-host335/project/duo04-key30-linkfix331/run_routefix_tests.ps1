$ErrorActionPreference='Stop'
$taskProject=$PSScriptRoot
$env:PATH='D:/FPGA_VIVADO/2025.2/Vivado/bin;'+$env:PATH
$env:TANGLAB_SIM_WORK='D:/codex/tasks/2026-11-01/mpu28-routefix/reproduce'
& "$taskProject/../../.venv/Scripts/python.exe" "$taskProject/run_gesture_tests.py" tb_mpu_equivalence tb_mpu_fusion tb_mpu_host tb_mpu_two_hand tb_scheduler_pipeline tb_scheduler_early_bend tb_wrist_group tb_wrist_voice tb_duo04_32 tb_wrist_audio tb_score27_uart tb_routefix2_capture2048
exit $LASTEXITCODE
