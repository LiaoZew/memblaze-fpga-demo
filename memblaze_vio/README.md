# MemBlaze FPGA (xc7k325tffg900-2) — VIO LED Demo (Vivado 2024.2)

## 1. IO 约束判定（依据三个资料文件）

### 1.1 依据文件

| 文件 | 作用 |
|---|---|
| `MEMBLAZE_PINS_V2.xls` | 板卡引脚总表（Sheet1：时钟/3 个 LED/JTAG；右下接插件：扩展连接器） |
| `ddr.xdc` | 参考设计的系统级约束（时钟、状态灯、SPIx4 bitstream 设置） |
| `ddr_72bit.ucf` | DDR3 72-bit 接口引脚约束（SSTL15 / DIFF_SSTL15） |

### 1.2 判定结果（本 demo 使用）

| 信号 | FPGA 引脚 | 电平标准 | 来源佐证 |
|---|---|---|---|
| `sysclk`（板载时钟 CLCK） | **D27** | LVCMOS18 | Sheet1：「时钟 CLCK D27 50M 1.8V 单端」；ddr.xdc：`PACKAGE_PIN D27` + `IOSTANDARD LVCMOS18` |
| `led_g`（绿色 LED_G） | **R24** | LVCMOS18 | Sheet1：`LED_G R24`；ddr.xdc：`init_calib_complete → R24` |
| `led_y`（黄色 LED_Y） | **T20** | LVCMOS18 | Sheet1：`LED_Y T20`；ddr.xdc：`heartbeat → T20` |
| `led_r`（红色 LED_R） | **T21** | LVCMOS18 | Sheet1：`LED_R T21`；ddr.xdc：`error → T21` |

### 1.3 DDR3 接口（ddr_72bit.ucf，本 demo 未使用，供后续参考）

- 72-bit 数据（`ddr3_dq[71:0]` = 64 数据 + 8 位 ECC）、`ddr3_dm[8:0]`、`ddr3_dqs_p/n[8:0]`
- 地址 `ddr3_addr[15:0]`、`ddr3_ba[2:0]`、单 rank：`ddr3_ck_p/n[0]`、`ddr3_cke[0]`、`ddr3_cs_n[0]`、`ddr3_odt[0]`
- 控制：`ddr3_ras_n / cas_n / we_n / reset_n`
- 电平：DQ/DM 为 `SSTL15_T_DCI`，DQS 为 `DIFF_SSTL15_T_DCI`，地址/命令为 `SSTL15`，复位为 `LVCMOS15`
- 已转换为参考 XDC：`reference/ddr3_72bit_converted.xdc`（注意：7 系列 VCCAUX 固定 1.8 V，`VCCAUX_IO HIGH` 无需保留）

### 1.4 其它已知引脚（Sheet1）

- JTAG：`TCK_0=E10, TMS_0=F10, TDI_0=H10, TDO_0=G10`（左下接插件）

## 2. 工程结构

```
memblaze_vio/
├── scripts/create_project.tcl     # 一键建工程 + VIO IP + 综合/实现/bitstream
├── src/top.v                      # 顶层：VIO 3 路输出 → 3 个 LED
├── src/memblaze_led.xdc           # 引脚/时钟/bitstream 约束
├── reference/ddr3_72bit_converted.xdc  # UCF→XDC 参考转换（未加入工程）
└── projects/memblaze_vio.xpr      # 工程（运行脚本后生成）
```

## 3. 使用方法

### 3.1 重新构建（命令行）

```
D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source scripts\create_project.tcl
```

或直接打开 `projects/memblaze_vio.xpr`（已含全部 IP/源码/约束）。

### 3.2 硬件联调（VIO 控 LED）

1. 打开 **Hardware Manager** → Open Target（连接 JTAG），Program Device，选择
   `projects/memblaze_vio.runs/impl_1/memblaze_vio_top.bit`
2. 在 **hw_vio** 窗口中选中 `vio_0`：
   - `probe_out0` → LED_G（R24）
   - `probe_out1` → LED_Y（T20）
   - `probe_out2` → LED_R（T21）
3. 勾选/取消即可点亮/熄灭对应 LED，实现在线控制。

> LED 亮度极性（高电平点亮 vs 低电平点亮）在引脚表末标注；若接反，
> 将 `top.v` 中 `assign led_* = vio_out*;` 改为取反（`= ~vio_out*;`）即可。
> 若不需要 JTAG 在线调试、希望上电按初始值显示，可将对应
> `C_PROBE_OUTx_INIT_VAL` 改为 1。

## 4. 已生成结果

- 工程：`projects/memblaze_vio.xpr`
- Bitstream：`projects/memblaze_vio.runs/impl_1/memblaze_vio_top.bit`