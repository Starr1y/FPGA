# DUO01 构建时序与验证

本版本集成双手传感器、双扇区 HDMI 和 32 Voice 数字音频。实板下载、真实两颗 IMU 和模拟音频尚未验证。

## 时序修正

首轮构建虽生成 `.fs`，但核心 Fmax 只有 42.844 MHz，50 MHz 约束下有 2253 个 setup 违例。该位流没有冻结、上传或下载。首轮报告保存在本地 `board-test/duo01/iteration0/`，用于追踪，不能作为发布证据。

关键路径经过音符映射与 Voice 配置更新：

- `dual_note_map.v` 将整数除法/取余换为有界 LUT，合法组合仍覆盖七音、五音、十二半音和三和弦。
- `dual_voice_scheduler.v` 给映射结果增加寄存器，音符提交前已有完整声部扫描时间；力度事件先保存，再更新本手同一 epoch/事件 ID 的声部。
- 取消和 epoch 失效仍优先处理，不缩短修订计数器，不用放宽时钟约束替代修复。
- `duo_panel.v` 用阈值选择中文字格，复位/停用/故障清除击发闪光，更换音区布局不显示旧布局的击发闪光。

`fpga/duo01/dependency-sources.json` 记录复制时的原始依赖哈希；DUO01 的音符映射和分配器随后按上述说明修改。冻结发布清单记录本版本实际源码哈希，不能用复制来源哈希代替它。FAN04 与原 `fpga/dualhand/rtl/` 保持原样。

## 检查入口

在项目根目录运行；Python 需要 Pillow，仿真需要 Icarus/vvp（Windows 当前使用 WSL Ubuntu）。

```powershell
python -X utf8 fpga/tools/check_duo_audio.py
python -X utf8 fpga/tools/duo01_release.py check
python -X utf8 fpga/tools/check_duo_board.py
python -X utf8 fpga/tools/duo01_release.py build
python -X utf8 fpga/tools/package_duo01.py
```

1. 音频检查：2048 个映射向量、8/32 Voice 真实 PCM 渲染，所有权、配置背压、模式快照、释放、声部满载替换。
2. 页面和按键：去抖/松键/组合键，8 张 RTL 画面、隐藏遥测不改变演奏页、边距、双手击发、故障、5/12 布局。
3. 原生板卡数字链路：50 MHz / 48 kHz，两个 100 Hz I²C 模拟传感器，独立归中、负 Z 击发、渐入渐出、实际 PT8211 串行字解码、单手停用隔离。测试缩短启动/复位等待，按键输出在该链路测试中被强制；物理按键语义由独立测试覆盖。
4. Gowin 构建：保持核心 20 ns 约束，检查所有 setup/hold 违例为零、Fmax 满足 50/25 MHz、引脚与原理图一致、I²C/RST 三态输出的输入确为常量零。
5. 打包：上述证据与源码哈希完全匹配后才生成冻结位流和清单；不能覆盖不同哈希的已有冻结固件。

本轮映射、8/32 Voice、按键和页面检查通过；新版 setup/hold 违例均为零，核心/像素 Fmax 为 50.123/27.371 MHz（实际约束 50/25 MHz），PR1014 通用时钟路由告警保留。50 MHz/48 kHz 原生完整数字链路已通过，两个 100 Hz 行为 IMU 完成独立归中、负 Z 和弦/旋律击发、静音渐变及单手停用隔离；解码 PT8211 的 83449 个串行字，其中 8136 个非零。已冻结 `fpga/bitstream/tanglab_duo01.fs`；结果以 `board-test/duo01/` 各验证 JSON 与冻结清单为准。

`prepare_duo01.py`、`assemble_duo01_board.py`、`populate_duo01_panel.py` 是初次创建工程的辅助脚本，日常修改与构建不要重跑它们覆盖现有 RTL。普通构建使用仓库已提供的 ROM；如另行重建字体，需从 `docs/reference/fonts/wenkai-source.json` 指定来源取得对应 TTF，核对哈希后放入所需字体路径。仓库不要求运行任何 PC 上位机程序。

## 实测范围

数字链路通过也不代表模拟输出、爆音、温度、真人动作识别率、漂移或 10 ms 延迟达标。按键手动使能也没有新增 PGOOD、电源限流或掉电隔离。单颗模块先保持静音验证，双手和声音等用户返回后分别实测。
