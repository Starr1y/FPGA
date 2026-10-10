# BNO085 串口上位机（STM32 验证版）

这是独立的 Python/Tkinter 测试工具，读取 STM32 测试固件输出的 BNO085 串口数据。支持原始与校正姿态/加速度/角速度、曲线、3D 姿态、七音区和 Pitch 下拍候选事件，以及原始与事件 CSV。当前不会发声，也不参与 FPGA 演奏闭环。

## 运行

1. 安装带 Tkinter 的 Python 3.11 或更新版本。
2. 在本目录执行 `powershell -ExecutionPolicy Bypass -File .\install.ps1`，安装 pySerial 到本目录的 `vendor/`。
3. 双击 `启动上位机.cmd`，或执行 `python app.py`。关闭其他占用串口的程序，选择 CH340 对应 COM 口后连接。串口固定为 115200、8N1。
4. 放稳设备，点击“静态初始化（3 秒）”。相对 Yaw 选择七个音区；相对 Pitch 明显向下拍动时确认击打。识别到的音区会短暂变色，单击音区图可放大。

“开始记录 CSV”会在 `recordings/` 默认目录或选定位置创建原始 CSV 和独立的 `_events.csv`。两个文件均不会覆盖已有文件。位置诊断页的 XYZ 数值仅为 IMU 积分演示，**不能用于测距或选音**。

当前 STM32 输出约 20 Hz，可能漏掉快速下拍峰值；击打时机与力度仅用于算法预研。外置按钮尚未进入串口协议，Pitch 抬手变频功能未做实物验证。真实设备验收应人工记录七个音区的轻重下拍及非击打动作，再与事件 CSV 比对。

## 离线检查

```powershell
python -B -m unittest discover -s . -p 'test*.py' -q
python -B app.py --smoke-test
```

`--smoke-test` 使用模拟数据，不打开 COM 口。源码只依赖 Python 标准库与 pySerial 3.5；`vendor/`、`recordings/`、`__pycache__/` 不上传。
