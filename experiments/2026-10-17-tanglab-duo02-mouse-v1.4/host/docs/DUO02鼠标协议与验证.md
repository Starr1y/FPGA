# DUO02-MOUSE 接口

固定基线为 `9e577cd06350327c956613da686851feb118dfb4`；新增UART测试顶层，复用真实32Voice、音色、双声道、FX、PT8211及HDMI。IMU未实例化。旧固件接口保持兼容，鼠标固件不执行旧的VOICE/PIANO/IMU控制。

帧沿用TangLab A5 5A、版本、类型、长度、序号、32位50MHz计数及CRC16。921600 baud，8N1。命令应答表示接受，不表示采样完成。

|命令|负载（小端）|作用|
|---|---|---|
|0x30|run, profileL, profileR, presetL, presetR, chord, effect, wet, gain 各u8|静音释放旧声音后配置；gain 0..64 /256|
|0x31|hand,valid,zone 各u8|预选，可合并旧位置|
|0x32|event_id u32,hand,zone,profile,octave,velocity,capture 各u8|逐次击发；octave为有符号-2..1；不自动重试|
|0x33|无|停止、清理FX|
|0x34|无|状态查询|
|0x35|无|心跳，GUI连接运行时每0.5秒；硬件2秒超时静音|
|0x11|trigger=0，可追加points u16（512/2048）|普通完整抓取，event_id=0|

ACK码0成功、1采集忙、2参数非法、3击发不可用/队列满。击发确认后等待0x89采样元数据和完整0x82样本才能判定采样完成。上传繁忙时击发仍接受，但同步抓取跳过计数增加。单缓冲不覆盖。

0x89元数据 `<HIIHBBH>`：capture_id、event_id、起始board_tick、配置revision、format=1、channels=5、reserved。五路固定为干声左/右、效果后左/右、效果后平均混音。0x88状态格式1共180字节，包含运行、选区、左右击发次数、32位活动mask、32个音符及32个包络；具体偏移以lab_duo.py解析为准。

## Agent

沿用 `/api/v1`、Bearer认证、任务查询及原TangLabCtl。新动作：

* `duo.configure`: `{"run":true,"profiles":[0,0],"presets":[0,0],"chord":false,"effect":0,"wet":128,"gain":8}`。
* `duo.select`: `{"hand":0,"zone":0,"valid":true}`。
* `duo.strike`: `{"hand":0,"zone":0,"profile":0,"octave":0,"velocity":32,"capture":true}`；event_id可省略，由上位机分配。
* `duo.stop`: `{}`。
* `duo.demo`: `{}`，明确模拟，不连接板卡。

profiles 0七音/1五音/2十二音；presets 0拨弦/1贝斯/2管乐/3铃音；effect 0旁路/1延迟/2合唱/3混响。既有capture/export/record/replay仍可用。GUI/API共享串口所有者，普通采样的等待不阻塞击发和停止。触发超时不重发，避免双重击发。

可给Codex或Claude Code的提示词：读取本目录说明，用TangLabCtl查询能力；只有DUO02-MOUSE才配置并逐次击发。每次记录设备接受与采样完成，匹配event_id，不将模拟数据写成实测；结束或失败执行duo.stop。不要独占另开串口，不自动烧录，不自动重试超时击发。

## 验证复现与边界

Python虚拟环境执行 `tests/check_duo.py` 检查GUI、映射、模拟十次击发、512/2048、暂停、导出、旧版兼容；`tests/check_live.py` 检查既有滚动采集。

`tests/check_duo_rtl.py --out 新的绝对输出目录` 调用Vivado XSim，生成真实UART字节，再由上位机解析器校验CRC、片段、起音编号、干声与效果后样本对齐、混音、左右隔离、32Voice、PT8211串行数据、KEY2及超时边界。仿真上传间隔100us，硬件保持10ms。`TANG_SIM`下不仿真Gowin TMDS原语；HDMI需上板人工确认。

Gowin在 `fpga/duo02-mouse` 中执行 `gw_sh.exe build.tcl`。交付的VERIFICATION.json记录实际位流校验值、时序/资源和验证状态；不沿用原DUO02时序结论。原冻结位流不修改。听音、显示器、真实串口十次击发仍需用户下载后验证。

## DUO02-MOUSE 1.1
0～256音量，默认32；左右保持0.1～5秒，默认1.5秒，释音0.2/0.5/1.5秒。新工程duo02-mouse-20261017，需自行重编译与烧录。旧1.0固件仍限制音量64并禁用保持控件。低幅值改为对称舍入，左右连续数字零20ms后关闭功放；模拟底噪仍需实测。详见鼠标音区音量与延音更新说明.txt。
配置0x30新增15字节扩展格式：原前8字节之后为gain u16、hold_left_ms u16、hold_right_ms u16、release_ids u8（左bits1:0，右bits3:2）；旧9字节格式仍接受。状态0x88格式2为186字节，原byte11为gain低8位，byte79 bit0为gain高位，bit1为actual_gain高位，180/182为左右保持ms u16，184为release_ids，185为功放关闭状态。握手1.1标记扩展能力。原格式1解析保持兼容。

## DUO02-MOUSE 1.2 音频修正
新工程duo02-mouse-1.2-20261017。增加钢琴（合成）及纯正弦校准音色，分别编号4/5。0～3保持旧音色编号。按键保持是松键时刻，释音是松键后的时间，钢琴自然衰减独立配置。
配置0x30新增20字节格式：原15字节之后是piano_hold flags u8（bit0左、bit1右）、Q24衰减系数left u16/right u16。系数27～4025对应约30～0.2秒T10；GUI以秒换算，默认6秒约134。旧9/15字节命令仍支持原四音色。
状态格式3共192字节，原186字节字段不变；186为piano_hold flags，187/189为左右系数u16。握手DUO02-MOUSE 1.2，capabilities.duo_quality=true、duo_presets=6。
Agent duo.configure新增piano_hold:[false,false]、piano_decay_s:[6,6]，仅1.2支持。voices.set仍属于旧四声部固件，不用于DUO02鼠标钢琴。
音频：每手16声部预留余量，效果后8倍响度补偿，联动限幅器峰值上限28000；相位表1024点；停止时渐变静音，取消逐音自动功放开关。音量最大256，同值不代表与旧版相同响度。
新增tests/check_audio_quality.py验证钢琴与限幅器。相位表量化误差的理论比较不代表板上模拟信噪比。实物听感待用户下载新固件后确认。
