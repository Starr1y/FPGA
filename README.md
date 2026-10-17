# TangLab：FPGA 姿态感知虚拟乐器

Tang Mega NEO / 138K，器件 `GW5AST-LV138PG484AC1/I0`。仓库只包含 FPGA 工程、硬件参考、构建与验证材料，不依赖 PC 上位机。

## 当前版本 DUO03

[工程](fpga/duo03/tanglab_duo03.gprj) · [下载位流](fpga/bitstream/tanglab_duo03.fs) · [冻结清单](board-test/duo03/firmware.json) · [接线与操作](docs/DUO03_统一控制与菜单接入.md)

- 两路独立 I²C，自主读取 BNO085；每手独立启停、归中、选区、击发和表情。
- KEY0 设置基准方向，前方 180° 非循环 7/5/12 音区；取消距离选音。
- 去重力的本体负 Z 加速度 ≤−2.5 m/s² **或**负向急动度 ≤−80 m/s³ 击发，含数据新鲜度、回位和防连击检查。
- 两个独立 16 Voice 池，共 32 Voice；四种音色、ADSR、尾音、旋律/和弦和 Roll/Pitch 表情。
- 独立左右声道、可调延迟/合唱/简化混响、静音渐变；PT8211 48 kHz / 16 位。
- 板载键、编码器、踏板、腕部按钮共用参数；菜单改动连接实际合成与音效链路。
- 双扇区演奏页、按键打开的诊断页、中文菜单；文楷字体、英文唱名、青色预选和品红击发。

**已完成数字验证与位流冻结，尚未下载或进行本版实物测试。** 上电两手未使能、静音；手动启停没有新增限流、PGOOD 或掉电隔离。返回后按[单手验证顺序](docs/DUO03_返回后单手验证.md)先确认启动来源，再接模块；SRAM 下载掉电后不保留。

## 常用板载操作

主页面所有动作在合格松键后执行，上电先松开全部按键。

| 操作 | 功能 |
| --- | --- |
| KEY0 短按 / 长按约 1.5 秒 | 当前手归中 / 切换 7、5、12 音区 |
| KEY1 短按少于 300 ms / 按住至少 300 ms | 当前手音色 / 表情 |
| KEY2 短按 / 长按约 1.5 秒 | 切换操作手 / 复位当前手 |
| KEY0＋KEY1 短按 / 长按约两秒 | 打开菜单 / 双旋律与左和弦右旋律切换 |
| KEY1＋KEY2 短按 / 长按约两秒 | 演奏与诊断切换 / 启停当前手 IMU |
| KEY0＋KEY2 长按约两秒 | 静音切换 |
| 三键短按 / 长按约两秒 | 湿声简易加档 / 切换音效 |

菜单内 KEY1 下一项/增加，KEY2 上一项/减少，KEY0 确认/退出编辑，KEY0 长按返回；KEY0＋KEY1 短按关闭。外部输入可先留空，用板载键完成操作。

## 接线

整体断电接线，使用实际测得的 3.3 V 和可靠共地。引脚已按 NEO Rev1.4 原理图追踪；新版本实体接线仍待核对。

| IMU 焊盘 | 手 0（左） | 手 1（右） |
| --- | --- | --- |
| SCL | E19 / J13.38 | D19 / J13.37 |
| SDA | C18 / J13.40 | C19 / J13.39 |
| INT | E16 / J13.28 | E17 / J13.31 |
| RST | D20 / J13.36 | F16 / J13.32 |

每颗模块 PS1、PS0、ADO、CS 共地，独立总线地址均为 0x4A。D14/D15/F15 留空；**J13.11 是 5 V，不能作 3.3 V**。F16 是第二手 RST，不能保留旧 SPI CS 接法。[六个外部无源触点输入表](docs/DUO03_统一控制与菜单接入.md)与 IMU 接线分别核对。

## 验证与资源

| 资源 | 使用/可用 |
| --- | --- |
| Logic | 49630/138240（35.9%） |
| Register | 22546/139095 |
| BSRAM | 80/340 |
| DSP | 83/298 |

setup/hold 零违例，核心/像素 Fmax **50.861/29.724 MHz**，实际约束 50/25 MHz；核心余量约 1.722%。相对 DUO02 增加 193 Logic、557 Register、6 BSRAM，DSP 不变。PR1014 通用时钟路由告警保留。

- 原始按键、编码器、踏板和腕部输入的统一参数与上下文检查通过。
- 2048 音符映射，8/32 Voice 的所有权、背压、取消、PCM 和 DAC 检查通过；32 Voice 场景最大合成 369 周期，无丢样或削波。
- 50 MHz/48 kHz 顶层连接两个 100 Hz 行为 IMU；独立归中、负 Z 旋律/和弦、静音、单手停用通过，解码 83449 个 PT8211 字，其中 7960 非零。
- 完整帧快照、256 个湿声百分比、13 张 RTL 画面，以及原始板载键/编码器到 RGB 检查通过。

仿真缩短部分等待，原生传感器链路使用强制参数激励，视频跳过厂商 PLL/TMDS 原语，边界记录在各 JSON。**这些证据不代表实物 HDMI、模拟声音或 ≤10 ms 延迟已通过。** 原生输出仍为 640×480 / 25 MHz；显示器缩放不等于多分辨率或 EDID 自动协商。

位流 SHA256：`35d614acc54a10d6de17f6ad111aa71a6643dc8dadb6d7c185c750e987b62c9a`。

## 构建和复核

Python 3 + Pillow，数字仿真使用 WSL Ubuntu/Icarus，构建使用 Gowin 1.9.12.03。RTL、ROM 已包含，普通构建不需要下载字体或运行上位机。

```powershell
python -X utf8 fpga/tools/duo03_release.py verify
python -X utf8 fpga/tools/check_duo03_controls.py
python -X utf8 fpga/tools/check_duo03_audio.py
python -X utf8 fpga/tools/check_duo03_video.py
python -X utf8 fpga/tools/check_duo03_board.py
python -X utf8 fpga/tools/check_duo03_board_video.py
python -X utf8 fpga/tools/duo03_release.py build
python -X utf8 fpga/tools/package_duo03.py
```

脚本不下载 SRAM/Flash；重构建不保证字节一致，打包拒绝以不同哈希覆盖冻结位流。[详细构建说明](docs/FPGA仓库构建与发布.md) · [许可与来源](THIRD_PARTY_NOTICES.md)

### 波形、频谱与 Voice 观测开发核心

[FPGA 内音频观测](docs/FPGA音频波形与频谱采集.md)已实现真实 PCM 的 1024 点双声道 FFT、64 列波形极值、64×2 频段及 32 Voice 元数据整帧缓冲。实际 32 Voice/混响/DAC 路径采样核对、两时钟像素读回和过载/复位检查通过。组合组件未布局综合为 Register 2000、LUT 1666、BSRAM 11、MULTALU27X18 2。

**尚未加入当前下载位流或绘制中文观测页**，没有整机新增时序或实物频谱结论。DUO03 保持原哈希，下一步接观测页面和实际 Voice 总线；WS2812、原生多分辨率与实测继续保留在完整任务范围。

## 未完成的验收

实际双 IMU、外部控制、模拟音频、真人识别率、十分钟漂移和两小时最大负载待测。Voice/实际音频波形、FPGA 频谱、WS2812 教学、原生多分辨率仍在完整任务范围内。详见[任务审计](docs/当前任务书执行与验收.md)。

[延迟记录工具与空白模板](docs/实机延迟记录与离线验收.md)已提供，七项合成数据检查通过；没有 1000 次实测数据，分析器通过仅表示进入原始波形复核。

## 目录和历史版本

| 目录 | 内容 |
| --- | --- |
| `fpga/duo03/` | 当前独立 RTL、ROM、约束、测试和工程 |
| `fpga/bitstream/`、`fpga/reports/duo03/` | 冻结位流、资源/时序/引脚报告 |
| `board-test/duo03/` | 数字证据、哈希、仿真画面 |
| `fpga/tools/` | 仿真、构建、冻结与离线实测统计工具 |
| `docs/` | 操作、任务书、参考原理图及许可 |

[DUO02](docs/DUO02_立体声与音效接入.md)、[DUO01](docs/DUO01_双手板卡接入与操作.md)、[FAN04](docs/I2C_FAN04_表情采样与验证.md)保持冻结，按各自文档使用。当前文件树不含上位机源码、GUI、EXE 或运行环境；历史提交保留原记录。
