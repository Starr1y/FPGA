# TangLab DUO04 上位机源码

Windows 10/11 x64；便携成品见上层 portable ZIP，无需 Python。
开发重建：使用 Windows x64 Python 建立虚拟环境，安装 requirements-lock.txt，运行 build_exe.py。

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-lock.txt
.\.venv\Scripts\python.exe build_exe.py
```

可通过当前进程环境变量 TANGLAB_BUILD_DIR 指定构建目录，默认本目录 build-cache。
不要更改系统 PATH/TEMP。Gowin/Vivado 等工具需配置自己的安装路径；EDA 许可证、硬件驱动另备。
fpga/duo04 为本次工程镜像，其余小型源码仅用于保留旧固件兼容入口，不附旧位流。
DUO04 的使用和接线以上层中文指南为准，旧指南只对应标题中标明的旧固件。
已附用户编译位流，PR1014 仍存在；重建软件不等于重新验证 FPGA。
