# TangLab：Tang Mega 138K 音频与 IMU 调试

中文 Windows 上位机与 Gowin 测试工程，适用于 **Tang Mega 138K 普通 Dock、C 版本**，器件 **GW5AST-LV138PG484AC1/I0**。当前交付固件 **TangLab 1.3.1（2026-10-08）**。

## 下载并使用

- **免安装上位机**：[前往 Releases 下载 TangLab Windows 64 位 ZIP](https://github.com/Starr1y/FPGA/releases/latest)。解压整个文件夹后运行 `TangLab.exe`，无需 Python。硬件连接另需驱动，编译下载另需 Gowin。
- **工程与烧录文件**：[`piano-tail-fix-20261008/`](piano-tail-fix-20261008/)，工程是 `tanglab.gprj`，固件是同目录 `tanglab-piano-v1.3.1.fs`。也可在 Releases 下载独立 FPGA 工程 ZIP。
- **操作说明**：先读[使用说明](使用说明.txt)、[钢琴设置](钢琴音色使用说明.txt)，接线与 SPI 测试见[两声部与 SPI 上板指南](两声部与SPI上板测试指南.txt)。
- **BNO085／STM32 验证上位机**：独立源码与启动说明见 [`bno085_pc/`](bno085_pc/README.md)。使用 115200 串口，与上面的 TangLab FPGA 工具分开运行。

先摘下耳机，用官方 Programmer 下载到 **SRAM**，断电后失效。确认板上时钟 **50 MHz**，上位机选择实际 DEBUG-USB2 串口，波特率 **921600**，握手应为 `TangLab 1.3.1`。上电默认静音；从低增益开始设置声部。

## 功能

- 四路独立声部与混音五路波形；独立缩放、横纵游标、中文右键菜单、暂停、导出。
- 512/2048 点完整抓取、自动重复抓取、最近一段/最近30段滚动历史。**分段采集，段间有空档**，不是无丢失流式示波器。
- FFT 幅度/相位谱，只分析完整单段；包络预览不能用于 FFT。
- 基本波形与合成钢琴、ADSR、钢琴保持/自然衰减；参数仍通过“应用四个声部”提交。
- IMU SPI、UART-SHTP、UART-RVC 调试、原始记录/回放及分测点延迟统计。
- Gowin 综合/布局布线日志，官方 Programmer 手动下载。
- 带随机会话令牌的本机 Agent API，配套 `TangLabCtl.exe`；详见[接口说明](docs/agent调试接口说明.md)。

## 目录

| 路径 | 用途 |
| --- | --- |
| `source/` | GUI、命令工具、协议、构建脚本及软件测试源码 |
| `bno085_pc/` | STM32＋单颗 BNO085 的 Python 串口验证上位机 |
| `run_tanglab.py` | 在仓库根目录启动源码版，正确查找说明和工程 |
| `fpga/` | 最新 RTL、testbench、CST/SDC、Gowin 工程 |
| `fpga/bitstream/tanglab.fs` | 与 1.3.1 集中工程完全相同的固件 |
| `fpga/impl/tanglab_process_config.json` | 必须保留的 IDE 配置，释放 CPU/SSPI 复用管脚作为 GPIO |
| `fpga/reports/` | 对应本版的综合、布局布线及完整时序报告 |
| `piano-tail-fix-20261008/` | 可直接复制的完整 1.3.1 工程、fs、报告与 SHA256 |
| `board-test/` | 两声部/SPI 参数与当前固件清单 |
| `docs/` | 通信协议、Agent API、验证边界及第三方引用 |

`fpga/tanglab-audio-spi-j9-20260923.fs` 是仓库保留的历史版本，请使用上述 **1.3.1** 入口。

## 源码启动与构建

Windows 10/11 64 位，Python 依赖见 `requirements-lock.txt`：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-lock.txt
.\.venv\Scripts\python.exe run_tanglab.py
```

构建脚本采用原交付目录布局。先生成独立目录，再在那里执行 `build_exe.py --package-only`：

```powershell
.\.venv\Scripts\python.exe tools/prepare_build.py D:/TangLab-build-new
Set-Location D:/TangLab-build-new
# 使用刚才安装依赖的 Python 环境运行：
python build_exe.py --package-only
```

`source/build_exe.py` 的 `WORK` 默认位于 D 盘，可按本机修改。需安装 PyInstaller；不要将 Python/EDA/运行记录上传到仓库。
Gowin 编译：在工程目录用 `gw_sh.exe build.tcl`；输出 `impl/pnr/tanglab.fs`，集中工程根目录交付 fs 不会自动覆盖。

## 验证状态与边界

- 上位机“旧应用完成覆盖新发声勾选”的竞态已修复；相关软件回归与最终 EXE 模拟检查通过。
- 1.3 实板：512/2048 各10段，CRC/缺包新增0；钢琴保持、衰减、松键及重复起音通过。
- 1.3.1 实板：明确松键后两次起音均成功、CRC/缺包新增0；**尾音、SPI、实际听音与模拟端到端延迟仍待验证**。
- 1.3.1 钢琴对称取整消除偏置尾音；16位 PCM 仍有低幅量化。相关 RTL 仿真通过。
- Gowin 1.9.12.03：50MHz 约束下 Fmax51.340MHz，最差 setup0.522ns，setup/hold TNS0；既存 PR1014 时钟路由警告仍保留。
- 不承诺控制到模拟音频 ≤10ms，不包含 HDMI 显示，不自动烧录。

详细记录见 [1.3.1修复与验证](docs/TangLab1.3.1修复与验证.txt)。第三方依赖、Qt/PySide6 与官方管脚来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)；运行依赖完整许可随便携 ZIP 分发。未擅自为本项目新增开源授权许可证。
