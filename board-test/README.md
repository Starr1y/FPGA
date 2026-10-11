# FPGA 发布范围核对

当前版本：FAN03。该目录的模拟图、数字检查日志和 Gowin 构建报告属于 FPGA 验证材料；不包含串口上位机程序。真人实测模板目前只有表头，没有样本。

- 15 项 RTL 仿真：`i2c-fan03/simulation.json`。
- 34 种实际 RTL 栅格画面：`i2c-fan03/render-validation.json`；数据为测试注入。
- 原始编译输入与位流哈希：`I2C负Z独立加速度或急动度固件清单.json`。
- 实机状态：`i2c-fan03/physical-validation.json`；FAN03 未下载，IMU 未连接，实测按用户要求延后。
- 表情扩展：`expression-rate/validation.json`；未合入当前位流。
- 旧根目录 JSON 为历史音频/通信实验，不代表 FAN03 整机验收。
