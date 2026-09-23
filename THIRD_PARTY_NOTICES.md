# 技术依据与许可证

## 参考源

本项目独立编写桌面 UI、串口传输、统计及记录层。协议字段、换算及帧规则参考以下代码；不直接运行 CircuitPython 库，不包含其硬件依赖。

- Adafruit_CircuitPython_BNO08x，MIT：
  https://github.com/adafruit/Adafruit_CircuitPython_BNO08x
  已核实提交：`a9aa286c6a0bea3b459a7eac53875658a62e3289`，提交日期 2026-04-23。
  阅读 `adafruit_bno08x/uart.py` 与 `__init__.py`；参考报告长度、Q 格式、配置帧。
- Adafruit_CircuitPython_BNO08x_RVC，MIT：
  https://github.com/adafruit/Adafruit_CircuitPython_BNO08x_RVC
  已核实提交：`96b4c299ac59934c943e8efccb54c4bc65142692`，提交日期 2026-04-23。
  阅读 `adafruit_bno08x_rvc.py`；参考 19 字节帧、校验和与量纲。上游示例文档存在 UART 参数混用，本项目以芯片规格书为准，RVC 固定 115200。
- CEVA SH-2 官方实现（协议核对，不复制代码）：
  https://github.com/ceva-dsp/sh2/blob/main/sh2.c
  2026-09-13 阅读 sensorhubInputHdlr / touSTimestamp，用于确认 base/rebase 的符号及 100 μs 单位。raw/master 获取失败后，从仓库实际 main 页面核对；未冒充已固定其提交。
- BNO08X Datasheet 1000-3927 v1.17，用户提供的 59 页 PDF，重点第 16–21、43–44、49–50 页。

## Adafruit MIT 许可声明

Copyright (c) 2020 Bryan Siepert for Adafruit Industries

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## 运行依赖

- PySide6 / Qt：LGPLv3/GPLv3/商业许可，按各组件许可分发；本项目使用独立安装的官方 wheel，不静态链接。
- pyqtgraph：MIT；pyserial：BSD；NumPy：BSD；各自完整许可随安装包保留。
- 便携 EXE 使用 PyInstaller 文件夹模式，依赖许可证在 licenses 目录。Qt/PySide6 以动态库分发，可替换兼容版本；允许为调试这些库的修改进行逆向工程。上位机源码随包提供，重建方法见使用说明.txt。
- Qt/PySide6 对应版本源码：https://download.qt.io/official_releases/QtForPython/ ，Qt 源码：https://download.qt.io/official_releases/qt/ 。具体组件以 licenses 内声明为准。
- 新版五通道显示继续采用 pyqtgraph：https://github.com/pyqtgraph/pyqtgraph （MIT）。
- 板卡管脚与工程配置参考 Sipeed 官方 https://github.com/sipeed/TangMega-138K-example （Apache-2.0）；官方管脚文件保留在 docs/reference。RTL 为本项目编写。
