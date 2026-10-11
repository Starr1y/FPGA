# FPGA 第三方来源与许可

## 字体

当前衍生点阵字库 **TangLab HDMI Bitmap** 由霞鹜文楷等宽 Medium v1.522 栅格化生成。Copyright 2021–2026 LXGW；Copyright 2020 The Klee Project Authors；衍生字形 Copyright 2026 TangLab contributors。原始字体及衍生字库遵循 SIL Open Font License 1.1，完整版权及许可见 [WenKai-OFL.txt](docs/reference/fonts/WenKai-OFL.txt)。字库使用自己的衍生名称，原字体来源署名保留。

原 TTF 用于开发，不嵌入 FPGA；本仓库提供生成的 RTL 点阵、完整 OFL 和 [原始字体版本、URL、SHA256](docs/reference/fonts/wenkai-source.json)。来源：[LXGW WenKai v1.522](https://github.com/lxgw/LxgwWenKai/releases/tag/v1.522)。

## HDMI 与 FPGA 工具

`svo_tmds.v` 来自 SVO - Simple Video Out FPGA Core，Copyright (C) 2014 Clifford Wolf。文件保留完整版权和许可，允许使用、复制、修改、分发并要求保留声明。PLL 包装代码来自 Gowin IP，保留文件内原厂版权声明。

板卡引脚与配置参考 Sipeed Tang Mega 示例（Apache-2.0），完整许可见 [Sipeed-LICENSE.txt](docs/reference/Sipeed-LICENSE.txt)。硬件参考为 [TangMega-138K-example](https://github.com/sipeed/TangMega-138K-example)。

BNO085 协议与报告字段依据 CEVA BNO08X Datasheet、Sensor Hub Transport Protocol、SH-2 Reference Manual，以及 [官方 SH-2 实现](https://github.com/ceva-dsp/sh2) 核对。当前驱动 RTL 为项目编写，没有复制 CEVA 驱动源码。

PNG 重生成工具使用独立安装的 Pillow，RTL 仿真使用独立安装的 Icarus Verilog，综合布局布线使用用户安装的 Gowin。此仓库不分发这些工具二进制。

历史音频 RTL 与当前静音 UI 版本分别保留，当前状态以 FAN03 清单和文档为准。项目自有源码未在本次发布中另行指定新许可证；上述第三方文件按各自许可处理。
