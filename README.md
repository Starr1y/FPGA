# TangLab FPGA

面向 **Tang Mega 138K 普通 Dock（C 版）** 的 FPGA 音频与 IMU 通路验证工程。Gowin 工程包含四声部数字音频、UART 通信、I²S 输出和 SPI IMU 接口；随附测试参数以两声部（375 Hz、750 Hz）和 SPI 为本轮验证目标。

> 当前文件夹是 FPGA 工程及测试资料，不含指南中提到的 `TangLab.exe`、`TangLabCtl.exe` 或 PC 端源码。已有位流来自先前编译，本轮尚未完成实物验证；模拟结果不能代替上板结果。

## 目录

| 路径 | 内容 |
| --- | --- |
| `fpga/tanglab.gprj` | Gowin 工程入口 |
| `fpga/rtl/` | Verilog RTL |
| `fpga/tb/`、`fpga/run_sim.py` | SystemVerilog 测试平台与 XSim 脚本 |
| `fpga/tanglab.cst`、`fpga/tanglab.sdc` | 引脚和时序约束 |
| `fpga/bitstream/tanglab.fs` | 已编译位流，供对应器件下载 |
| `fpga/reports/` | 原编译报告，作为随附构建记录保留 |
| `board-test/` | 上板测试参数和固件清单 |
| `docs/协议与测量.md` | 串口协议及测量口径 |
| `docs/reference/` | 引脚参考资料及其原始许可文件 |
| `两声部与SPI上板测试指南.txt` | 接线、下载和验证步骤 |

## 环境与构建

1. 使用 **Gowin EDA** 打开 `fpga/tanglab.gprj`。工程目标器件为 `GW5AST-LV138PG484AC1/I0`；请先核对实际板卡型号。
2. RTL 和约束文件均位于 `fpga/` 下。修改 RTL 后，在 Gowin 中重新综合、布局布线，检查资源及时序报告，再生成新位流。`fpga/build.tcl` 提供 `run all` 构建脚本。
3. 只需验证现有固件时，可使用 `fpga/bitstream/tanglab.fs`，无需重新构建。其型号、SHA-256 和来源记录在 `board-test/固件清单.json`。

系统时钟约束为 **50 MHz**，PC 串口为 **921600 baud**，音频采样率约 **48 kHz**。这些参数和测试口径见 `docs/协议与测量.md`。

## 仿真

`fpga/run_sim.py` 使用 Vivado XSim 的 `xvlog`、`xelab`、`xsim`，例如在 PowerShell 中：

```powershell
python .\fpga\run_sim.py --bench tb_audio --out .\fpga\sim-out\audio --vivado 'C:\Path\To\Vivado\bin'
```

可选测试平台为 `tb_audio`、`tb_imu`、`tb_lab`。其中 `tb_lab` 还会调用 PC 端的 `lab_engine` 和 NumPy；当前文件夹缺少 `lab_engine`，因此单独检出本仓库后不能运行该平台的完整 Python 校验。请按实际安装位置修改 `--vivado`。

## 上板验证

先阅读 [`两声部与SPI上板测试指南.txt`](./两声部与SPI上板测试指南.txt)，确认普通 Dock C 版器件、引脚方向和 **3.3 V** 电平，再接线和下载。真实测试参数见 `board-test/two-voice-spi.json`；`board-test/simulation.json` 仅用于无板卡模拟。指南中的 PC 端 EXE 不在本仓库中，需要另行取得才能执行其 GUI 或命令行步骤。当前状态为**待实物验证**。

## 版本管理约定

`.gitignore` 排除 Gowin 自动生成的 `fpga/impl/`、个人配置、仿真缓存和本机测试结果。`fpga/bitstream/tanglab.fs` 与 `fpga/reports/` 是本次随附的交付记录，会纳入 Git；位流约 35 MB，首次推送会较大。不要提交本机串口配置、记录数据或密钥。参考 PDF 的许可信息见 `docs/reference/Sipeed-LICENSE.txt`。
