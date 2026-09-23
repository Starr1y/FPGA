# TangLab

TangLab 是面向 **Tang Mega 138K 普通 Dock（C 版）** 的 FPGA 数字音频与 IMU 通信实验工程。FPGA 提供四声部音频合成、I²S 输出、UART 帧通信及 IMU 接口；Windows 上位机提供波形、频谱、参数配置和板卡测试工具。当前工程**没有 HDMI 显示逻辑**。

## 项目内容

| 路径 | 内容 |
| --- | --- |
| `fpga/rtl/`、`fpga/tanglab.gprj` | Gowin FPGA 源码及工程；目标器件 GW5AST-LV138PG484AC1/I0 |
| `fpga/bitstream/tanglab.fs` | 2026-09-23 候选固件，供相同板型先用 SRAM 下载验证 |
| `fpga/reports/pnr/` | 与候选固件对应的布局布线报告；`gwsynthesis/` 为较早的报告 |
| `fpga/tb/`、`fpga/run_sim.py` | RTL 仿真及与 Python 解包联测入口 |
| `source/` | Windows 图形界面、控制工具、协议和测试源码 |
| `board-test/` | 上板参数、仿真结果与固件校验清单 |
| `docs/`、`使用说明.txt`、`两声部与SPI上板测试指南.txt` | 协议说明、操作与接线文档 |

## 快速开始

1. 核对板型、器件型号和供电方式，按 `两声部与SPI上板测试指南.txt` 接线。IMU 使用 PMOD0/J9，信号电平为 3.3 V。
2. 用 Gowin Programmer 将 `fpga/bitstream/tanglab.fs` 下载到 **SRAM**。下载前用 `board-test/固件清单.json` 核对 SHA256。
3. 启动 Windows 上位机，选择板卡 DEBUG-USB2 对应串口，以 921600 baud 握手；先调低耳机或音箱音量，再设置声部参数。
4. 开发者可在安装 `source/requirements-lock.txt` 中的依赖后运行 `source/tanglab.py`；Gowin 工程入口为 `fpga/tanglab.gprj`。仿真脚本需要另行提供 Vivado/XSim 路径。

详细使用方式和安全接线以 `使用说明.txt` 与上板指南为准。Git 仓库存放源码、文档、固件和报告；`TangLab.exe`、`TangLabCtl.exe`、`_internal/` 是可重新构建的便携发布产物，默认不纳入版本管理。

## 当前验证状态（2026-09-23）

- 四声部、I²S、UART 解包与抓取的仿真已有通过记录；候选固件的布局布线报告和文件校验值已归档。
- 先前实板调试已观察到串口握手、参数设置及非零数字预览数据；此前完整抓取遇到丢包或 CRC 问题。
- 本版加入约 10 ms 的抓取分包间隔，但**尚未在实板上复测完整抓取**。SPI IMU 通信、模拟音频输出、端到端延迟及 HDMI 显示均未完成实测验收。
- `fpga/reports/gwsynthesis/` 是较早版本的综合报告；判断本候选固件时序时应查看 `fpga/reports/pnr/`。布线报告不能代替实板验证。

工程状态详见 `docs/交付验证.txt`，第三方依赖见 `THIRD_PARTY_NOTICES.md`。
