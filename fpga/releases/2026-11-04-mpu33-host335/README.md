# 双MPU6050 33连接修复版与TangLab 3.3.5配套归档

归档日期：2026-11-04。本目录发布当前本地完整演奏主线：**33／3.3.1连接修复固件＋TangLab 3.3.5上位机**。它是双MPU6050工程，不是仓库`fpga/current`的“左MPU＋右BNO”V14冻结工程，也不是双音色Lite分支。原工程、位流、上位机及仓库历史不覆盖。

## 直接使用

- [完整打包下载](downloads/TangLab-MPU33-Host335-complete.zip)：含FPGA工程、ROM、约束、现有`.fs`、报告、上位机完整便携目录和开发源码。全部解压后运行`portable/TangLab.exe`，不要只复制EXE。
- [FPGA源码工程](project/duo04-key30-linkfix331/tanglab_duo04_key30_linkfix331.gprj)，顶层`top_duo04`；必要IDE配置位于工程的`impl/*_process_config.json`。
- [现有位流](bitstream/tanglab_duo04_key30_linkfix331.fs)，由用户在Gowin Programmer中手工下载；本次没有重新综合、布线或烧录。
- [上位机源码](host/source/)；入口`lite29.py`，依赖见`host/source/requirements-lock.txt`。`host/TangLab335.spec`和`host/build.ps1`是使用相对路径的重打包入口，原始构建规格与日志保存在`host/build/`。
- [发布状态](IMPLEMENTATION_STATUS.json)与[原始报告](reports/)；校验见`MANIFEST.json`、`SHA256SUMS.txt`和压缩包校验文件。

## 保留的功能

双GY-521独立I²C、S1击发及俯仰C3/C4/C5锁档、S2组合滑音和长按腕部表情；钢琴、马林巴、电钢琴、拨弦四音色；32复音、左右各16声部；左手单音／三音和弦；保持、释音、立体声混音和音效；1024×600 HDMI、本地按键与EC11菜单；整体波形；图片/PDF视觉AI转谱、外部JSON、校验上传及最多2048步板端逐音教学。

3.3.5电脑输入仅为调试及演示入口，声音合成和教学判题仍在FPGA。键盘统一轻音，反馈期间不提前缓存下一题；教学页支持主键盘与数字小键盘的左右手七音作答。实物S1按压时长力度逻辑仍属于固件，不把上位机轻音修改误写成固件变化。

## 当前接线与起步

| 信号 | 左手J13／FPGA管脚 | 右手J13／FPGA管脚 |
|---|---|---|
| SCL | 38／E19 | 37／D19 |
| SDA | 40／C18 | 39／C19 |
| S1 | 25／D15 | 26／D14 |
| S2 | 28／E16 | 31／E17 |

两颗GY-521使用独立总线，AD0均接GND；XDA/XCL/INT不接。本分支不是INT驱动V14。常开按键另一端接公共GND，模块和总线使用已核对兼容的3.3V供电与逻辑。EC11：A=J13.1/E14，B=J13.2/E13，按压S=J13.3/C15；与板卡共地。音频使用板载PT8211及3.5mm模拟口连接耳机或有源音箱。

初次先静音，选择真实手柄来源，静置等待准备后归中，再开始演奏；单侧离线不要求另一侧也离线。S1锁存音区和C档，S2控制最近音组。鼠标、数字键与教学使用方法见[3.3.5说明](host/数字教学使用说明.txt)。AI密钥在使用者本机配置，本包不携带任何现有密钥或用户记录。

## 构建与实际状态

使用Gowin工程器件`GW5AST-LV138PG484AC1/I0`、顶层`top_duo04`。工程已有相对路径Tcl入口，`build_selected.tcl`执行全流程，`synth_only.tcl`仅综合。核心50MHz、音频48kHz，Route Option=2、时序驱动及保持修正配置随工程保留。ROM必须与RTL一起保留。重新构建会在本工程自己的`impl`产生中间文件，不需要本次排除的大型数据库。

本地2026-11-03 18:18:35报告显示布局布线及位流生成完成，但**setup违例238、最差setup slack −5.009ns、hold违例0，PR1014仍在**，不能称为时序闭环或完整实物验收。资源：Logic 75383/138240、寄存器32626/139095、BSRAM140/340、DSP106/298。没有将无ERROR或生成`.fs`等同于时序通过。

工程内`BUILD_STATUS.json`及部分历史说明写于综合布线之前，原样保留用于追溯；本次状态以根目录`IMPLEMENTATION_STATUS.json`及随包原始报告为准。本次只做打包、校验及离线上位机检查，不启动EDA、不连接串口、不调用真实AI或烧录。实物听音、手感和教学推进仍应由实际设备确认。

## 源码与重新打包

在Windows 64位Python环境安装`host/source/requirements-lock.txt`，使用`python host/source/lite29.py`运行源码；在`host/`执行`powershell -File build.ps1 -Python <Python路径>`生成新便携目录。新构建不保证与现有EXE逐字节一致，应重新验证。发布包包含现有运行时和第三方许可，按项目来源及许可使用。

发布目录不含EDA许可证、API密钥、会话令牌、记录、曲库、Python缓存、仿真数据库及大型布局布线中间数据库。原有本地文件均不删除。
