# TangLab：FPGA 姿态感知虚拟乐器

Tang Mega NEO / 138K，器件 `GW5AST-LV138PG484AC1/I0`。本仓库仅维护 FPGA 工程、硬件参考、构建工具与验证材料。

## 新版本 DUO01

[Gowin 工程](fpga/duo01/tanglab_duo01.gprj)，顶层 `top_duo01`；[冻结位流](fpga/bitstream/tanglab_duo01.fs)，HDMI 核对 **DUO01**。

- 两条独立 I²C 总线，每手独立启停、归中、选区、击发与表情；单颗 IMU 可先验证左手。
- KEY0 设置方向基准，前方 180° 非循环，支持 7/5/12 音区，保留 3° 边界滞回与越界保护。
- 击发为模块自身负 Z 的已去重力加速度 `az ≤ −2.5 m/s²` **或**急动度 `jz ≤ −80 m/s³`，无须同时转腕；20 ms 静稳回位、100 ms 防连击及数据陈旧保护。
- 两个独立 16 Voice 池，总计 32 Voice；四种音色、ADSR、和弦/旋律模式、每手力度/弯音/颤音/明亮度。
- 双扇区 HDMI，中文提示、英文 DO RE MI FA SOL LA SI；青色预选、品红击发。演奏页隐藏姿态/通信细节，组合键切换诊断。
- 板载 PT8211，48 kHz / 16 位；当前为单声道混音复制左右，默认静音，切换静音使用增益渐变。

**数字验证已冻结；本版本尚未下载或实物验证。** 真实双手、模拟声音、动作延迟与漂移指标仍待测。开机两个 IMU 都未使能；手动启用不提供供电检测、限流或掉电隔离。

### 接线与操作

整体断电后接线，供电使用实际测得的 3.3 V，GND 共地。引脚球位和长排针号按 NEO Rev1.4 原理图追踪。

| IMU 焊盘 | 手 0（左） | 手 1（右） |
| --- | --- | --- |
| SCL | E19，J13.38 | D19，J13.37 |
| SDA | C18，J13.40 | C19，J13.39 |
| INT | E16，J13.28 | E17，J13.31 |
| RST | D20，J13.36 | F16，J13.32 |

每颗模块 PS1、PS0、ADO、CS 接该模块共地节点，独立总线均用地址 0x4A。D14/D15/F15 留空。**J13.11 是 5 V，不能作为模块 3.3 V。** F16 在新版本用于第二手 RST，不能保留旧 SPI 的 CS 接法。

| 实物按键 | 松开后操作 |
| --- | --- |
| KEY2 短按 | 切换当前操作的手 |
| KEY2 长按约 1.5 秒 | 复位当前手 |
| KEY0 短按 | 归中当前手 |
| KEY0 长按约 1.5 秒 | 切换当前手 7/5/12 布局 |
| KEY1 短按（小于 300 ms） | 切换当前手音色 |
| KEY1 按住至少 300 ms | 启用当前手 Roll/Pitch 表情；松开停止颤音 |
| KEY1＋KEY2 短按 | 演奏/诊断页 |
| KEY1＋KEY2 长按约 2 秒 | 启停当前手 IMU |
| KEY0＋KEY2 长按约 2 秒 | 静音切换 |
| KEY0＋KEY1 长按约 2 秒 | 双旋律/左和弦右旋律 |

完整引脚、按键和测试顺序：[接入与操作](docs/DUO01_双手板卡接入与操作.md)，[返回后的单手测试表](docs/DUO01_单手返回测试表.md)。首次保持静音，确认单手在线、归中、慢速选区和负 Z 击发后，再测试声音和第二手。

### 验证和资源

| 资源 | 已用/可用 |
| --- | --- |
| Logic | 48365/138240（约 35%） |
| Register | 21500/139095 |
| BSRAM | 40/340 |
| DSP | 71/298 |

setup/hold 违例为零，核心/像素 Fmax 50.123/27.371 MHz（约束 50/25 MHz）；核心余量较小，PR1014 通用时钟路由告警保留。HDMI 原生 640×480、约 59.52 Hz，显示器缩放不等于原生多分辨率/EDID 协商。

- 2048 个映射向量，8/32 Voice 实际 PCM 渲染及所有权/背压/取消/满载检查通过。
- 组合键、去抖、松键语义及 8 张 RTL 光栅画面通过；隐藏遥测不改变演奏页。
- 50 MHz / 48 kHz 板卡数字链路通过：两个 100 Hz 行为 IMU，独立归中、负 Z 和弦/旋律、静音渐变、单手停用隔离；解码 83449 个 PT8211 串行字，其中 8136 个非零。
- 原生数字链路缩短启动/复位等待，并强制按键控制输出；物理键语义另测。未模拟厂商 TMDS 原语，不代表实物 HDMI、模拟音频或整机 ≤10 ms 延迟通过。

[构建与验证说明](docs/DUO01_构建时序与验证.md)，[冻结清单](board-test/duo01/firmware.json)，[任务书进度与验收](docs/当前任务书执行与验收.md)。

## 双声道音效开发

独立模块 [stereo_fx.v](fpga/effects/rtl/stereo_fx.v) 已实现旁路、反馈延迟、分数插值合唱及简化四抽头混响，左右缓存独立。三个仿真检查通过，包括默认 RAM 的 33000 个采样；独立综合为 32 BSRAM、720 LUT。

**尚未接入 DUO01，也没有音效板卡位流或实物听音证据。** 参数、综合范围和下一步见 [音效开发说明](docs/双声道音效开发与验证.md)。

## 构建与目录

在仓库根目录运行。Python 3 + Pillow；仿真用 WSL Ubuntu/Icarus，构建用 Gowin 1.9.12.03。仓库已提供 RTL 和 ROM，不需要 PC 上位机。

```powershell
python -X utf8 fpga/tools/duo01_release.py verify
python -X utf8 fpga/tools/check_duo_audio.py
python -X utf8 fpga/tools/duo01_release.py check
python -X utf8 fpga/tools/check_duo_board.py
python -X utf8 fpga/tools/duo01_release.py build --gowin-shell "D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"
```

脚本不下载 SRAM/Flash。重新构建不保证位流字节一致；冻结文件不能覆盖为不同哈希。生成辅助脚本只用于首次创建，不能重跑覆盖已审核的时序修正。

| 目录 | 内容 |
| --- | --- |
| `fpga/duo01/` | 当前独立 RTL、ROM、测试、约束和工程 |
| `fpga/bitstream/`、`fpga/reports/duo01/` | 冻结位流及资源/时序/引脚报告 |
| `board-test/duo01/` | 数字检查日志、源码哈希及模拟画面 |
| `fpga/dualhand/` | 双手核心与数字音频开发基线 |
| `fpga/effects/`、`board-test/stereo-fx/` | 独立音效模块与验证 |
| `fpga/tools/` | FPGA 仿真、构建、校验和实测统计工具 |
| `docs/` | FPGA 操作、任务书、硬件参考和字体许可 |

[完整仓库构建说明](docs/FPGA仓库构建与发布.md)。上位机源码、EXE、GUI 和运行环境不在当前上传内容中；历史提交仍保留原记录。[第三方声明](THIRD_PARTY_NOTICES.md)。

## 单手静音基线 FAN04

[FAN04 工程](fpga/i2cfan04/tanglab_i2c_fan04.gprj)、[位流](fpga/bitstream/tanglab_i2c_fan04.fs) 保持冻结，19 项仿真与 34 张画面通过，Logic 12.6%。与 DUO01 的物理按键及第二手接线不同，使用时遵循 [FAN04 操作说明](docs/I2C_FAN04_表情采样与验证.md)。FAN03 等历史版本供追溯。
