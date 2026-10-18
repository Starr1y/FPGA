# DUO04-LIVE 2.0：四音色、双IMU、脱机菜单与上位机

2026-10-18 独立交付，新增目录，不覆盖仓库原 DUO02、DUO03 或 2026-10-17 的1.4快照。由DUO03传感器/控制链路与DUO02-MOUSE1.4音频、串口、监测链路整合而来。

- **直接运行上位机**：[Windows10/11 x64便携ZIP](portable/TangLab-DUO04-LIVE-2.0-Windows-x64.zip)。打开文件页选择 Download raw，解压整个文件夹，运行 `TangLab.exe`；不用安装Python。驱动与Gowin工具另装。
- **Gowin工程**：[fpga/tanglab_duo04.gprj](fpga/tanglab_duo04.gprj)，顶层 `top_duo04`，器件 `GW5AST-LV138PG484AC1/I0`。
- **本次用户编译的位流**：[tanglab_duo04.fs](fpga/bitstream/tanglab_duo04.fs) · [构建、资源与SHA256](fpga/FIRMWARE.json)。与当前独立工程放在同一 `fpga` 目录内。
- **先读**：[接线与上板指南](接线与上板指南.md) → [上位机与脱机操作指南](上位机与脱机操作指南.md)。
- **进度**：[比赛要求完成情况](比赛要求完成情况.md)；[已知问题与下一步](已知问题与下一步.md)。
- **源码**：[上位机与构建脚本](host/)、[FPGA RTL/ROM/TB](fpga/)、[实际验证证据](validation/)。

## 这次实际完成到哪里

硬件实时计算钢琴、马林巴、电钢琴、反馈拨弦四音色；32独立声部（左右各16）、48kHz立体声、按音符保存的保持时间及释音、音效、可选滑音/颤音。PC只发送事件与参数，不向FPGA播放录制PCM。单正弦是独立校准源，不计入32个演奏声部。

脱机演奏、电脑鼠标、逐音教学三种模式；双独立I²C/BNO085、EC11菜单、四页HDMI和本机Agent接口均有代码集成。上位机保留512/2048点分段采集、32声部状态、最多4路所选声部真实PCM及共享波形面板。

**源码实现、数字仿真、布线报告、实物验收不是同一层结论。** 用户已生成本次.fs；16:24报告setup/hold均零违例，最差setup余量+0.299ns，核心Fmax50.758MHz。**PR1014仍在，尚未完成整机验收。** 实物独立客户端三次识别DUO04，但HDMI插拔关联的通信故障尚未隔离；双IMU、编码器、教学与音质仍需逐项上板。

本版**没有上位机虚拟编码器/HDMI菜单导航入口**。PC可改演奏模式与参数，但HDMI页面切换仍用实体EC11；无IMU的鼠标演奏不能代替传感器教学推进。实体LED教学、≤10ms/≤5ms实测、手机/无线功能未完成。

## 下载和校验

下载由用户在官方Programmer执行；SRAM下载掉电失效。本次上传没有重新综合、布局布线或自动烧录。

```powershell
Get-FileHash .\fpga\bitstream\tanglab_duo04.fs -Algorithm SHA256
```

本次.fs SHA256：`db441bdca7228b0710b2ae63d986a49bf0d76c5b28610555c2c20f40b2a93726`。
`SHA256SUMS.txt`覆盖本快照的源码、位流、报告和便携ZIP。窗口程序须连同 `_internal` 等依赖整个解压使用，不能只复制一个EXE。

不包含个人记录、Agent会话令牌、虚拟环境、Gowin许可证或EDA中间数据库。第三方许可随包保留；本快照不对第三方内容重新授予许可。
