# 2026-10-17 TangLab 与 DUO02-MOUSE 1.4 独立快照

本目录新增保存今天的上位机和测试工程，不替换仓库原 DUO02、DUO03 工程、约束和冻结位流。测试工程源自 DUO02 `9e577cd06350327c956613da686851feb118dfb4`；上传时仓库主线为 `6d557303d433b9fff2b897313c6c959621092396`。

- [下载 Windows 10/11 x64 便携程序](portable/TangLab-Windows-x64-v1.4.zip)：点击文件页的 Download raw；解压整个文件夹，运行 TangLab.exe。无需 Python。保留所有运行依赖；硬件驱动、Gowin 工具另装。
- [今天的 FPGA 工程](fpga/tanglab_duo02_mouse.gprj)：用 Gowin IDE 打开，ROM、RTL、CST、SDC 与 impl 内必要工程配置保持相对位置。
- [比赛要求完成情况与待办](比赛要求完成情况.md)
- [鼠标上板指南](fpga/鼠标音区上板测试指南.txt)
- [上位机使用说明](host/使用说明.txt)
- [可读上位机源码](host/)；含依赖锁定、测试及 build_exe.py。重建时可修改脚本 WORK 临时输出目录；使用 Windows 64 位 Python 创建 .venv，安装 requirements-lock.txt，再运行 build_exe.py。host/fpga 保留历史兼容支持；本轮编译以本目录顶层 fpga 工程为准。
- [验证记录](validation/)；SHA256SUMS.txt 校验本快照全部交付文件。

## 版本与验证边界

本轮固件为 **DUO02-MOUSE 1.4**，与旧四声部 TangLab 1.3.1 不同。32 声部、鼠标音区、钢琴、可选滑音/颤音、校准正弦、最多四声部真实 PCM 监测和共享波形面板供联调。鼠标分支关闭 IMU，PC 发送事件/参数，音频在 FPGA 合成。

1.4 RTL 数字仿真与打包 GUI/CLI 模拟检查已通过，不能代替真实听音、板上延迟、资源和时序验收。按用户要求，本轮不执行 Gowin 综合、布局布线和下载，**没有新增可认定为 1.4 的 .fs**。ZIP 中历史兼容位流不属于今天的固件。用户自行编译本轮工程后在 Programmer 下载。

`clk_d` 的 PR1014 普通布线时钟警告尚未解决；应检查最终时序、时钟偏斜和报告，不能仅以生成位流判定合格。PA2122 的钢琴状态存储已采用寄存器实现；本轮实际综合映射仍由用户检查。钢琴合成音色、响度与尾音的新改动尚待上板听音。

不包含个人记录、Agent 会话令牌、虚拟环境或 Gowin 许可证。第三方组件许可随包保留；本快照不额外授予第三方内容的许可。
