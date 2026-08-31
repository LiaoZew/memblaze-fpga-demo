# MemBlaze FPGA (xc7k325tffg900-2) — MicroBlaze LED Demo (Vivado/Vitis 2024.2)

## 概述

一个**最简单的 MicroBlaze 软核工程**，通过 **AXI（AXI-GPIO）接口控制板上 3 个 LED**：

```
MicroBlaze (50 MHz, 无 Cache)
 ├── AXI-Lite ──> AXI GPIO (3-bit 输出) ──> led[2:0] → LED_G/R24, LED_Y/T20, LED_R/T21
 ├── LMB 本地 BRAM (64 KB, 程序运行于此)
 └── MDM (JTAG 调试/下载程序)
```

## 工程结构

```
mb_led/
├── scripts/create_project.tcl   # 一键：工程 + Block Design + 综合/实现/bitstream + bin + xsa
├── scripts/build_elf.tcl        # Vitis/xsct 编译软核程序得到 dist/mb_led.elf
├── src/mb_led.xdc               # 引脚/时钟/bitstream 约束（与 led_demo 相同）
├── src/main.c                   # 软核代码：AXI 写寄存器控制 LED 闪烁
└── README.md
```

## 硬件构建（一条命令）

```
D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source mb_led/scripts/create_project.tcl
```

产出（自动发布到 `dist/`）：

| 文件 | 说明 |
|---|---|
| `dist/mb_led.bit` | 硬件 bitstream（含 MicroBlaze + AXI GPIO + MDM） |
| `dist/mb_led.bin` | SPIx4 flash 镜像（上电自启动硬件；软核程序仍需从 JTAG/Vitis 加载，见下） |
| `dist/mb_led.elf` | 软核程序（standalone，AXI 写 GPIO 控制 LED） |
| `mb_led/mb_led.xsa` | 硬件平台导出文件（供 Vitis） |

> 注意：MicroBlaze 调试走 **MDM 的专用 JTAG 口**（不经 debug hub），因此**没有 .ltx 文件**，属正常；程序下载用 xsct/Vitis 直接连 MDM。

## 软件构建（Vitis）

```
D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat mb_led\scripts\build_elf.tcl
```

产出 `dist/mb_led.elf`（standalone 程序：AXI GPIO 依次点亮/熄灭 LED）。

## 下载运行

1. **烧硬件**：`vivado -mode batch -source dist/program_flash.tcl -tclargs mb_led.bin`（把软核工程镜像烧入 flash）
   或 Hardware Manager → Program Device 选 `dist/mb_led.bit`（JTAG，调试用）。
2. **下软核程序**（xsdb / xsct Tcl）：
   ```tcl
   connect
   target
   targets -set -filter {name =~ "*MicroBlaze*"}
   rst -processor
   dow dist/mb_led.elf
   con
   ```
   LED 开始按 main.c 的模式闪烁（G+Y+R → 灭 → G+R）。

> 说明：`mb_led.bin`（冷启动硬件）不包含软核程序；工程上电后 MicroBlaze 需
> 从外部加载程序（JTAG/调试），或后续在 main.c 里加 XIP/Bootloop 方案，
> 也可用 `updatemem` 把 ELF 合并进 BRAM 后生成自启动 bit。

## 寄存器（AXI 接口）

- AXI GPIO 基地址见 `xparameters.h`（`XPAR_AXI_GPIO_0_BASEADDR`，默认 0x40000000）
- `+0x00` 数据寄存器：bit0=LED_G，bit1=LED_Y，bit2=LED_R
- main.c 用 `XGpio_DiscreteWrite()` 封装访问；直接读写法也等价。

## 常用命令速查

```text
# 硬件：建工程 + 综合/实现 + bit/bin + xsa
vivado -mode batch -source mb_led/scripts/create_project.tcl

# 软件：编译 ELF
xsct.bat mb_led/scripts/build_elf.tcl

# 调试下载（xsdb）
connect / targets / rst -processor / dow dist/mb_led.elf / con
```