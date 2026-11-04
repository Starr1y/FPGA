# TangLab：FPGA 姿态选音乐器

## 最新双MPU完整主线配套归档 2026-11-04

新增 **33／3.3.1双MPU6050连接修复工程＋TangLab 3.3.5数字教学上位机**，包含可浏览RTL/ROM/约束、上位机源码及构建入口、现有`.fs`、原始报告、完整便携程序和SHA256。

- [版本目录与接线、使用说明](fpga/releases/2026-11-04-mpu33-host335/README.md)
- [完整配套ZIP](fpga/releases/2026-11-04-mpu33-host335/downloads/TangLab-MPU33-Host335-complete.zip)
- [归档状态](fpga/releases/2026-11-04-mpu33-host335/IMPLEMENTATION_STATUS.json) · [本次打包及离线检查](fpga/releases/2026-11-04-mpu33-host335/PUBLICATION_CHECKS.json)

该分支为双MPU、四音色、32复音、S1/S2、和弦、整体波形和AI曲谱教学完整主线，区别于下方V14混合传感器冻结成果。现有位流已生成，但报告仍有setup违例238、最差−5.009ns、PR1014，**未标记为时序闭环稳定版**。本次未运行EDA或自动烧录，也未覆盖`fpga/current`或旧上位机。

## 原V14冻结成果说明

原冻结发布：**V14 / 2026-11-02，左手 MPU6050 + 右手 BNO085，外接按钮发声**。不是双 MPU6050。正式演奏链路由 FPGA 执行，PC 上位机用于调试与曲谱导入。

- [当前工程与操作](fpga/current/README.md) · [位流](fpga/current/bitstream/MPU_LEFT_YFORWARD_V14_TIMING_PASS.fs)
- [三分钟演示拍摄脚本](docs/三分钟演示拍摄脚本.md)
- [任务书逐项对照与剩余工作](docs/任务书对照_20261102.md)
- [接线与无声排查](docs/V14接线与操作.md) · [仓库清理与历史恢复](docs/版本清理与恢复.md)

完整布局布线已通过：Setup **+0.029 ns**、Hold **+0.164 ns**、未布通网络 **0**；PR1014 告警保留。这是数字实现结果，不能替代整机实测。当前用户已反馈左路可在线、可归中及选区；仍报告归中后方向异常、区域手感不均、按钮拉低后无声，不能称为整机验收完成。

显示为 **1024×600、49 MHz、约59.852 Hz**；画面逻辑仍由640×480布局映射并旋转180°。七音区默认覆盖−90°到+90°，FA边界约±12.875°，每区约25.714°，有3°滞回及30 ms确认。

## 快速开始

1. 断电按[接线表](docs/V14接线与操作.md)接线。左 MPU 不是接右手接口。
2. Gowin Programmer 手动将上述 `.fs` 下载到 SRAM。断电后需重新下载。
3. KEY0 归中成功后，**从主页面短按并松开旋钮，打开“快捷设置”，第一项确认开始演奏**。归中完成不等于已启动音频。
4. 松开发声按钮再按下；IMU只选音，运动本身不击发。默认音量仍为 **8 / 256**，按需调高。用户要求的默认80尚未进入此冻结位流。

下一版已确定：**双手MPU6050、默认音量80**，单独构建与验收，不替换本次V14冻结记录。

## 工程与验证

使用 Gowin V1.9.12.03，器件 `GW5AST-LV138PG484AC1/I0`。在 `fpga/current/` 打开 `.gprj`，或运行 `gw_sh build_selected.tcl`；RTL、ROM与约束已包含，不需要外置STM32。

```powershell
python tools/verify_current_release.py
python tools/run_current_regressions.py --iverilog-bin <Icarus的bin目录>
```

校验工具区分冻结输入、位流和原始构建记录；回归输出写到独立目录，不覆盖冻结证据。仿真通过不代表实板声音、双手、延迟或长稳已通过。

本次上传前已从归档目录重跑六项回归，全部通过，见[本轮验证记录](verification/v14-publication-20261102/VERIFICATION.json)。没有重新运行EDA或自动烧录板卡。

## 仓库组织

| 入口 | 内容 |
| --- | --- |
| `fpga/current/` | 唯一当前FPGA工程、位流、ROM、测试、构建和报告 |
| `experiments/2026-10-29-GEST26-stable/` | 保留的历史稳定基线；传感器和击发方式与V14不同 |
| `host/TangLab-2.7.2-Windows-x64.zip` | 远端已有上位机包原样保留；不承诺所有V14 MPU诊断字段均已适配 |
| `docs/` | 当前操作、任务对照、演示脚本、硬件参考与历史文档 |

旧迭代从当前工作树移除，保留在清理前的Git标签和提交历史中；没有重写历史。`docs/`中早期文档保留作历史依据，其完成状态和旧路径不得替代上述当前入口。第三方许可见[来源说明](THIRD_PARTY_NOTICES.md)。
