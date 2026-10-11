# FPGA 仓库构建与发布

仓库仅发布 FPGA 工程及其开发/验收材料。Python 仿真、构建和实测统计脚本属于 FPGA 开发工具，不是上位机应用；不包含串口 GUI、上位机源码、EXE、依赖环境或运行会话。

## 当前入口

- 工程：`fpga/i2cfan03/tanglab_i2c_fan03.gprj`；顶层 `top_i2c_fan03`。
- 已冻结位流：`fpga/bitstream/tanglab_i2c_fan03.fs`；屏幕标记 FAN03。
- RTL 与 ROM：同工程 `rtl/`；仿真：同工程 `tb/` 与 `fpga/tb/tb_video_hdmi.sv`。
- 资源/时序/引脚报告：`fpga/reports/i2c-fan03/`。
- 数字验证与模拟画面：`board-test/i2c-fan03/`；不是实机测量。

文件保持发布时字节，Git 属性禁止候选工程及证据自动换行转换。旧版位流哈希在清单中仅作为本机历史构建审计，不要求重新下载全部历史版本。

## 核对与仿真

需要 Python 3 和 Icarus Verilog。Windows 可安装原生 Icarus，或在 WSL Ubuntu 内安装 `iverilog`、`vvp`。在仓库根目录执行：

```powershell
python -X utf8 fpga/tools/fan03_release.py verify
python -X utf8 fpga/tools/fan03_release.py check
```

`verify` 核对冻结源码、ROM、约束、位流及 34 张 PNG 的 SHA256；`check` 独立重跑 15 项 RTL 仿真。新日志只写 `board-test/fan03-rebuild/`。无需运行上位机，无需连接 FPGA。

实际 RTL 画面重生成脚本 `render_i2c_fan03.py` 使用 WSL Ubuntu + Icarus，PNG 转换使用 Pillow。它会重写 `board-test/i2c-fan03/` 的模拟画面与渲染记录，因此建议先复制仓库到临时目录再运行，避免覆盖冻结证据。

## Gowin 构建

本次验证工具为 Gowin 1.9.12.03，目标 `GW5AST-LV138PG484AC1/I0`，50 MHz 核心、25 MHz 像素时钟。IDE 中打开上述工程并设置顶层，CPU/SSPI 复用管脚释放选项见 `build.tcl`。也可执行：

```powershell
python -X utf8 fpga/tools/fan03_release.py build --gowin-shell "D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"
```

新输出在 `fpga/i2cfan03/impl/`，日志在 `board-test/fan03-rebuild/`；不会自动覆盖已发布位流、下载到板卡或写 Flash。必须复查新输出的时序、引脚和版本标记；不同工具环境不保证位流字节完全一致。

## 扩展与实测记录

`fpga/extensions/hand_expression_rate.v` 为单独验证的 100/200 Hz 表情滤波扩展，未集成进 FAN03。验证入口为 `check_expression_rate.py`。实测 CSV 及 `analyse_gesture_trials.py` 用于用户回来后统计动作；当前模板无真人样本，不证明准确率或延迟达标。

## 后续 Git 上传

使用独立克隆作为发布目录，避免在包含个人文件的父目录执行 `git add .`。先同步审核后的 FPGA 文件，再检查差异并提交：

```powershell
git clone https://github.com/Starr1y/FPGA.git FPGA
cd FPGA
git status --short
git diff --stat
git add fpga docs board-test README.md 使用说明.md THIRD_PARTY_NOTICES.md .gitignore .gitattributes
git diff --cached --stat
git commit -m "Update FPGA firmware and validation"
git push origin main
```

本次正常提交保留 Git 历史，从最新文件树移除上位机；历史提交仍可查看旧文件，没有重写历史或强制推送。
