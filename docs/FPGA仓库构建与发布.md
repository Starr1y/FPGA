# FPGA 仓库构建与发布

仓库仅发布 FPGA 工程及其开发/验收材料。Python 仿真、构建和实测统计脚本属于 FPGA 开发工具，不是上位机应用；不包含串口 GUI、上位机源码、EXE、依赖环境或运行会话。

## 当前入口

- 工程：`fpga/i2cfan04/tanglab_i2c_fan04.gprj`；顶层 `top_i2c_fan04`。
- 已冻结位流：`fpga/bitstream/tanglab_i2c_fan04.fs`；屏幕标记 FAN04。
- RTL 与 ROM：同工程 `rtl/`；仿真：同工程 `tb/` 与 `fpga/tb/tb_video_hdmi.sv`。
- 资源/时序/引脚报告：`fpga/reports/i2c-fan04/`。
- 数字验证与模拟画面：`board-test/i2c-fan04/`；不是实机测量。

文件保持发布时字节，Git 属性禁止候选工程及证据自动换行转换。旧版位流哈希在清单中仅作为本机历史构建审计，不要求重新下载全部历史版本。

## 核对与仿真

需要 Python 3 和 Icarus Verilog。Windows 可安装原生 Icarus，或在 WSL Ubuntu 内安装 `iverilog`、`vvp`。在仓库根目录执行：

```powershell
python -X utf8 fpga/tools/fan04_release.py verify
python -X utf8 fpga/tools/fan04_release.py check
```

`verify` 核对冻结源码、ROM、约束、位流及 34 张 PNG 的 SHA256；`check` 独立重跑 19 项 RTL 仿真。新日志只写 `board-test/fan04-rebuild/`。无需运行上位机，无需连接 FPGA。

实际 RTL 画面重生成脚本 `render_i2c_fan04.py` 使用 WSL Ubuntu + Icarus，PNG 转换使用 Pillow。它会重写 `board-test/i2c-fan04/` 的模拟画面与渲染记录，因此建议先复制仓库到临时目录再运行，避免覆盖冻结证据。

## Gowin 构建

本次验证工具为 Gowin 1.9.12.03，目标 `GW5AST-LV138PG484AC1/I0`，50 MHz 核心、25 MHz 像素时钟。IDE 中打开上述工程并设置顶层，CPU/SSPI 复用管脚释放选项见 `build.tcl`。也可执行：

```powershell
python -X utf8 fpga/tools/fan04_release.py build --gowin-shell "D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"
```

新输出在 `fpga/i2cfan04/impl/`，日志在 `board-test/fan04-rebuild/`；不会自动覆盖已发布位流、下载到板卡或写 Flash。必须复查新输出的时序、引脚和版本标记；不同工具环境不保证位流字节完全一致。

## 扩展与实测记录

`fpga/extensions/hand_expression_rate.v` 为单独验证的 100/200 Hz 表情滤波扩展，已作为 FAN04 的基础并接入序号/时间戳保护；FAN03 保持冻结。验证入口为 `check_expression_rate.py`。实测 CSV 及 `analyse_gesture_trials.py` 用于用户回来后统计动作；当前模板无真人样本，不证明准确率或延迟达标。

## 双手开发核心仿真

FAN04 位流保持冻结。双手开发代码在 `fpga/dualhand/`，新板卡顶层在 `fpga/duo01/`，已冻结数字验证版本；数字音频和传感器集成的验证入口为：

```powershell
python -X utf8 fpga/tools/check_dual_audio.py
python -X utf8 fpga/tools/check_dual_audio.py --native-only
```

两份音频证据位于 `board-test/dual-audio/`。前者为 50 MHz/48 kHz 事件注入，后者为 1 MHz/2 kHz 原生传感器模拟链路；详细边界见 [双手音频说明](双手数字音频集成与验证.md)。

## DUO01 板卡工程检查

```powershell
python -X utf8 fpga/tools/check_duo_audio.py
python -X utf8 fpga/tools/duo01_release.py check
python -X utf8 fpga/tools/check_duo_board.py
python -X utf8 fpga/tools/duo01_release.py build --gowin-shell "D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"
```

`check` 检查组合键及 8 张 RTL 光栅画面；`check_duo_board.py` 用 50 MHz/48 kHz 板卡顶层接两个 100 Hz 行为 IMU，并解码 PT8211 串行数据。启动/复位等待缩短、按键输出用测试激励，不等于实物测试。新工程源码已包含所需 RTL/ROM 快照，无上位机依赖；只需 Python、Pillow、WSL Ubuntu/Icarus 和构建时的 Gowin。

脚本均不会下载 SRAM 或 Flash。构建结果需确认时序、引脚与源码哈希后才能执行 `package_duo01.py` 冻结；2026-10-12 已完成冻结，清单为 `board-test/duo01/firmware.json`，位流为 `fpga/bitstream/tanglab_duo01.fs`。`duo01_release.py verify` 同时核对冻结位流、源码、画面与音频/板卡数字链路输入哈希；不会执行下载。接线与新按键见 [操作说明](DUO01_双手板卡接入与操作.md)，时序修正和检查边界见 [构建与验证](DUO01_构建时序与验证.md)，返回后单颗模块的测试见 [测试表](DUO01_单手返回测试表.md)。

## 当前 DUO02 冻结版本

工程 `fpga/duo02/tanglab_duo02.gprj`，位流 `fpga/bitstream/tanglab_duo02.fs`，清单 `board-test/duo02/firmware.json`。算法 1 重建后 setup/hold 零违例，Fmax 50.026/26.542 MHz，核心余量很小。数字验证通过，尚未下载；[操作说明](DUO02_立体声与音效接入.md)与[返回后验证](DUO02_返回后单手验证.md)。

```powershell
python -X utf8 fpga/tools/duo02_release.py verify
python -X utf8 fpga/tools/check_duo02_audio.py
python -X utf8 fpga/tools/check_duo02_output.py
python -X utf8 fpga/tools/check_duo02_board.py
python -X utf8 fpga/tools/duo02_release.py check
python -X utf8 fpga/tools/duo02_release.py build
```

UI 校验比较 RTL/ROM/testbench 文件集合及哈希；布线脚本和约束由独立构建快照/冻结清单校验。仅修改布线算法不改变已有 RTL 仿真结果，不能因此删除时序检查或冒充已验证新的逻辑。

外部控制、参数菜单绘制和跨时钟联动是独立开发组件，检查入口为 `check_performance_controls.py`、`check_menu_display.py`、`check_menu_bridge.py` 和 `synth_menu_display.py --bridge`；尚未接入 DUO02 的主显示/音频/板卡引脚。其 GPRJ 只用于综合检查，不能作为完整可下载板卡工程。

## 后续 Git 上传（FPGA 范围）

本机原 Git 根目录误设为 `C:/Users/10324`，不要在那里执行 `git add .`。本次使用独立克隆 `C:/Users/10324/Documents/Codex/2026-10-11/FPGA-publish-fan03`；后续先将审核后的 FPGA 文件同步到该克隆，检查 `git status`、`git diff` 后再提交。

```powershell
cd C:/Users/10324/Documents/Codex/2026-10-11/FPGA-publish-fan03
git status --short
git diff --stat
git add fpga docs board-test README.md 使用说明.md THIRD_PARTY_NOTICES.md .gitignore .gitattributes
git diff --cached --stat
git commit -m "Update FPGA firmware and validation"
git push origin main
```

本次正常提交保留 Git 历史，从最新文件树移除上位机。历史提交仍可查看旧文件；没有重写历史或强制推送。
