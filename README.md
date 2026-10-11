# TangLab：FPGA 姿态感知虚拟乐器

适用 Tang Mega 138K / Tang Mega NEO，器件 `GW5AST-LV138PG484AC1/I0`。本仓库当前仅维护 FPGA 工程与相关验证材料。

## 当前版本：FAN03

- [下载位流](fpga/bitstream/tanglab_i2c_fan03.fs)，[Gowin 工程](fpga/i2cfan03/tanglab_i2c_fan03.gprj)，顶层 `top_i2c_fan03`；HDMI 核对 **FAN03**。
- 单颗 BNO085，通过 FPGA I²C 读取姿态，无需上位机参与演奏控制。
- KEY0 设置基准方向，前方 180° 非循环选音，支持 7/5/12 音区；当前音频静音。
- 沿模块自身负 Z 轴的已去重力加速度 `az ≤ −2.5 m/s²` **或**急动度 `jz ≤ −80 m/s³` 独立击发，无需同时转腕。20 ms 静稳回位、100 ms 防连击，时间戳/陈旧数据保护。
- 中文界面、英文唱名 DO RE MI FA SOL LA SI；青色预选、品红击发。演奏页隐藏通信和姿态细节，按键切换诊断页。

## 接线与操作

整体断电接线，VCC 使用实际测得的 3.3 V，GND 共地。SCL=E19、SDA=C18、INT=E16、RST=D20；PS1、PS0、ADO、CS 接模块 GND 节点，D15 留空。安装时模块 +Z 朝上；模块 −Z 不保证在任意倾斜时都等于世界竖直向下。

| 按键 | 操作 |
| --- | --- |
| KEY1＋KEY2 长按约 2 秒再松开 | 启停 IMU 通信 |
| KEY1＋KEY2 短按再松开 | 切换演奏/诊断页 |
| KEY0 短按再松开 | 在线时设置方向基准、归中 |
| KEY0 长按再松开 | 切换七音/五音/十二半音 |
| 实物 KEY2 长按 | 复位 |

完整步骤、回位门槛和 T1/T2/T3 击发原因见 [FAN03 操作与验证](docs/I2C_FAN03_负Z独立击发与验证.md)。

## 验证状态

15 项 RTL 仿真和 34 种实际 RTL 画面检查通过；模拟画面注入测试数据，不能作为实机证据。综合和布局布线完成，setup/hold 违例为零。

| 资源 | 已用/可用 |
| --- | --- |
| Logic | 17147/138240（约 12.4%） |
| Register | 6342/139095 |
| BSRAM | 15/340 |
| DSP | 21/298 |

核心/像素 Fmax 为 50.107/34.213 MHz；核心相对 50 MHz 余量较小，原 PR1014 告警保留。位流 SHA256：`3cbd1f235e4589f9f3e57f8b46e2cd3503dc2681decdec212dfad5b6e06ae1ed`。

**本次 FAN03 未下载或做真实 IMU 验证。** 用户确认 IMU 未连接，实测等返回后进行。完整目标中的双手、音频和量化指标仍未完成；见 [任务书进度与验收](docs/当前任务书执行与验收.md)。

## 构建和目录

[独立构建、校验与 Git 发布说明](docs/FPGA仓库构建与发布.md)；无需 PC 应用源码即可核对或仿真当前版本。

```powershell
python -X utf8 fpga/tools/fan03_release.py verify
python -X utf8 fpga/tools/fan03_release.py check
python -X utf8 fpga/tools/fan03_release.py build --gowin-shell "D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"
```

| 目录 | 内容 |
| --- | --- |
| `fpga/i2cfan03/` | 当前独立 RTL、ROM、testbench、CST/SDC、Gowin 工程 |
| `fpga/bitstream/tanglab_i2c_fan03.fs` | 当前冻结位流 |
| `fpga/reports/i2c-fan03/` | 对应资源、时序与引脚报告 |
| `fpga/tools/` | FPGA 校验、仿真、构建与实测统计工具 |
| `fpga/extensions/` | 100/200 Hz 表情滤波扩展，已单独仿真，尚未合入 FAN03 |
| `board-test/i2c-fan03/` | 数字检查记录和 34 张模拟画面 |
| `board-test/physical-trials/` | 实测记录模板，目前无真人样本 |
| `docs/` | FPGA 操作、任务书、硬件参考与许可证 |

已有 `fpga/tanglab.gprj`、旧位流和 `piano-tail-fix-20261008/` 为历史音频工程；它们不是 FAN03，也不提供当前 HDMI 页面。历史构建与旧版本哈希仅供追溯。

上位机源码、EXE、Python GUI 及运行环境已从当前文件树移除；原 Git 历史保留。新上传不包含上位机应用。[第三方声明](THIRD_PARTY_NOTICES.md)。
