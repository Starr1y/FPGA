两声部＋SPI 测试资料

先阅读上一级《两声部与SPI上板测试指南.txt》。
烧录文件在 ../fpga/bitstream/tanglab.fs；源码、CST/SDC 与原编译报告都在 ../fpga。
固件清单.json 记录 SHA256、原编译时间和适配板型，不冒充本轮重新编译。

two-voice-spi.json：真实板卡自动测试参数，需要先握手。
simulation.json：明确的模拟测试，不生成 SPI 实测结果。
two-voices.json：375/750 Hz 两声部低增益预设，另外两路关闭。
spi-mode.json：SPI 模式编号 2，运行后会复位 IMU。
spi-reports.json：姿态/加速度/角速度各请求 100 Hz。
立即抓取.json：立即抓取，避免静音时一直等过零触发。

自动流程入口：
TangLabCtl.exe run test.two_voice_spi --file board-test/two-voice-spi.json
不要直接双击 TangLabCtl.exe；请在 PowerShell 运行命令。
