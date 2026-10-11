# 当前 FPGA 字体

FAN03 使用 TangLab HDMI Bitmap 点阵，来自霞鹜文楷等宽 Medium v1.522，SIL OFL 1.1。完整许可：[WenKai-OFL.txt](WenKai-OFL.txt)。原始 TTF 下载地址与 SHA256 见 [wenkai-source.json](wenkai-source.json)，本仓库不保存完整 TTF，综合只使用 `fpga/i2cfan03/rtl/video_font*.v` 中需要的点阵。

FAN03 中文采用 24 像素字符单元，数字采用 8×12，音名使用加大英文字符。当前字形与布局以冻结 RTL 为准。字体生成源的版本、版权和衍生名称见根目录第三方声明。
