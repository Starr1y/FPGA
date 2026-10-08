# 本机 agent 调试接口

打开 TangLab →「07 agent 调试」→「开启本机接口」。界面始终持有板卡串口，agent 不应另开 pyserial 或其他串口工具。

接口只监听 `127.0.0.1`，优先使用 18738，端口冲突时自动改用空闲端口。不要写死地址；`TangLabCtl.exe` 自动读取同目录 `.agent-session.json`。关闭接口时该文件被删除，下一次开启会换令牌。所有 API 请求均需 `Authorization: Bearer <token>`；不接受浏览器跨源请求，不提供远程访问或任意代码执行。

## 命令行

在 TangLab 文件夹内打开 PowerShell，以下命令不需要 Python。参数复杂时使用 `--file`，避免 Windows 命令行引号问题。

```powershell
.\TangLabCtl.exe --help
.\TangLabCtl.exe status
.\TangLabCtl.exe capabilities
.\TangLabCtl.exe ports
.\TangLabCtl.exe run demo
.\TangLabCtl.exe run voices.set --file .\board-test\two-voices.json
.\TangLabCtl.exe run capture --file .\board-test\立即抓取.json
.\TangLabCtl.exe spectrum 4
.\TangLabCtl.exe run export
.\TangLabCtl.exe run voices.release
.\TangLabCtl.exe run test.two_voice_spi --file .\board-test\simulation.json
```

真实测试请先在 GUI 连接实际 COM，再使用 `board-test/two-voice-spi.json`。也可通过命令连接：在 UTF-8 JSON 文件中写入 `{"port":"实际COM编号"}`，执行 `run connect --file 路径`。

选项：`--session 路径` 指定会话文件；`--timeout 300` 设置等待秒数；`--no-wait` 提交后立即返回任务编号。

```powershell
.\TangLabCtl.exe --no-wait run eda.build
.\TangLabCtl.exe eda
.\TangLabCtl.exe job 任务编号
.\TangLabCtl.exe cancel 任务编号
```

命令工具默认等待任务完成，输出 JSON。退出码：0 表示调用完成；1 表示任务失败、取消或测试报告存在失败项目；2 表示参数、连接或等待超时错误。`--no-wait` 返回成功只表示排队成功，必须继续查询结果。客户端等待超时不会自动撤销任务，可用任务编号查询或取消。

## 查询 API（GET）

| 路径（均以 `/api/v1` 开头） | 内容 |
|---|---|
| `/status` | 数据来源、握手、设备能力、声部参数、统计、当前任务 |
| `/capabilities` | 支持动作列表与固件能力 |
| `/ports` | 串口列表与驱动描述 |
| `/reports` | IMU 模式、各类计数、配置应答、最新报告、最近原始包 |
| `/capture` | 最近完整采样、采样率、五通道数组；没有完整样本时报错 |
| `/spectrum/0`～`/spectrum/4` | 各声部/混音的幅相谱；被屏蔽的相位为 null |
| `/jobs/编号` | 状态、阶段历史、结果或错误 |
| `/events` | 最近操作记录，不包含令牌 |
| `/eda` | GUI 当前工程、编译状态、退出码及原始日志 |

## 命令 API（POST `/api/v1/commands`）

请求形如 `{"action":"capture","params":{"trigger":0}}`。返回 HTTP 202 和任务编号。硬件操作逐条应答后推进；长任务串行执行，不会占用绘图线程。界面按钮与 API 共用此调度入口。

| action | params 与行为 |
|---|---|
| `connect` | `port`：实际串口；默认 921600 baud，可通过 baud 参数指定，等待设备握手 |
| `disconnect` / `demo` | 无参数；断开或进入明确标注的模拟演示 |
| `voices.set` | `voices` 数组；`channel` 0～3，其余可选：hz、gain、wave、gate、attack、decay、sustain、release |
| `voices.release` | 四路松键，等待每路 ACK |
| `capture` | `trigger`：0 立即、1 混音上升过零；等待完整采样后才完成 |
| `preview` | `enabled` true/false；开启或关闭包络传输 |
| `imu.mode` | `mode`：0 RVC、1 UART-SHTP、2 SPI；复位后等待 2 秒，不自动确认传感器就绪 |
| `imu.configure` | `reports`：报告编号到 Hz 的映射；默认 5/1/2 各 100；等待传感器配置应答 |
| `ping` | 一次 PC/FPGA 往返测量，模拟不生成实测时延 |
| `record.start` | 可选 `name`；保存到 agent-results/唯一目录/recording，不覆盖已有目录 |
| `record.stop` | 完成记录保存 |
| `replay` | `path`：包含 metadata.json 和 raw.jsonl 的记录目录；会断开当前硬件并等待回放结束 |
| `export` | 可选 `name`；导出采样、五路幅相谱及统计 |
| `eda.synthesis` / `eda.build` | 对 GUI 已选择工程启动综合或完整编译；等待退出并返回日志 |
| `eda.stop` | 请求停止当前编译；不下载、不执行自定义 shell |
| `test.two_voice_spi` | `simulation` 默认 false；`reports_per_type` 默认 1000（1～1000）；`imu_timeout_s` 默认 120（1～120） |

声部参数：hz 1～20000，gain/sustain 0～1，wave 0 正弦/1 锯齿/2 方波/3 三角/4 钢琴（合成，需固件1.2及piano能力），gate 为布尔值，起音/衰减/释音 0～5000 ms。钢琴会自然衰减；重复敲击时，先等待voices.release完成，再提交gate=true的voices.set。低音量中央C示例：hz=261.63、gain=0.002、wave=4、gate=true、attack=3、decay=5000、sustain=0、release=100。

任务阶段：queued（已排队）→ running（执行中）→ acknowledged（设备已应答）→ completed（所需结果完成）。模拟使用 simulated 阶段，不伪造设备 ACK。`failed` 与 `cancelled` 是失败/取消；多命令任务可能交替出现执行中和已应答。保留最近 200 个任务，可用历史判断停在哪一步。

POST `/api/v1/jobs/编号/cancel`，请求体 `{}`，取消当前等待或排队任务。取消不代表 FPGA 当前已触发的采样能够撤销；过零触发若一直静音，可按板上复位键恢复。自动测试取消后仍尝试停止记录、关闭预览并松键，清理结果写入报告。设备已断线时无法保证松键，需要人工复位。

请求体上限 64 KiB。401 表示令牌/来源错误；404 表示路径、任务或必填字段不存在；400 表示参数或当前状态不支持。不会把队列成功、设备 ACK、完整采样成功混为同一结论。

## 给 Codex 桌面版或 Claude Code 的提示词

把工作目录切换到解压后的 TangLab 文件夹，再将以下内容交给 agent。无需修改 Codex/Claude 配置，也无需安装 MCP。

> 使用当前目录 TangLabCtl.exe，通过已开启的本机接口调试 Tang Mega 138K。先运行 status、capabilities、ports，确认数据来源和握手。不要直接占用串口，不要读取或打印 .agent-session.json 的令牌。使用 board-test/two-voices.json 设置两声部，抓取、检查声部一 375 Hz 和声部二 750 Hz、三四静音，并导出结果。确认我已经按指南接好 SPI 后，执行 board-test/two-voice-spi.json 对应的自动测试。读取最终测试报告，逐项区分实测通过、失败、待人工确认和未执行；不要把模拟或软件耗时称为端到端延迟。不要自动下载固件或修改引脚。失败先查看任务 history 和 events，结束后确认已经松键及停止记录。

若无硬件，用 simulation.json；SPI 项必须保持“未执行”。分享软件只发送干净 ZIP，不发送 .agent-session.json 或 agent-results。

波特率选择：主窗口串口旁可选择 115200～3000000 的预设波特率，默认 921600。必须与 FPGA 固件一致；选择后重新连接才生效。Agent connect 支持整数 baud 参数，status 返回实际 baud。

## 固件1.3新增可选参数

`voices.set`的每路可加`piano_hold`（布尔值）、`piano_decay_s`（0.2～30秒，默认6）。先等0x16配置应答成功，再发送原声部参数；旧固件显式请求会失败。基本波形不受影响。保持要求gate=true、gain和sustain大于零。关闭保持后从当前能量衰减；只改参数不会重敲。

`capture`可加`points`为512或2048，省略仍2048，512需要能力`capture_sizes`包含512。`piano_control`表示保持/衰减支持。状态新增每路`piano_settings`。

示例：`TangLabCtl.exe run voices.set --json '{"voices":[{"channel":0,"wave":4,"gate":true,"gain":0.002,"sustain":0.7,"piano_hold":true,"piano_decay_s":6}]}'`

示例：`TangLabCtl.exe run capture --json '{"points":512,"trigger":0}'`

两声部SPI自动测试保持既有2048点流程。
