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

## JTAG UART 串口调试（控制 LED）

软核通过 **MDM 内置的 JTAG UART**（USB-JTAG 虚拟串口，无需板载 UART 引脚）收发命令。
程序启动后打印提示并等待命令：

| 命令 | 作用 |
|---|---|
| `0`~`7` | 直接设置 LED[2:0]（bit0=G、bit1=Y、bit2=R），如 `5`=G+R 亮 |
| `G` / `Y` / `R` | 单独切换 绿 / 黄 / 红 |
| `h` | 打印帮助 |

**打开串口终端**（任选其一）：

```text
# xsct 命令行（推荐，无需 IDE）
D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat
xsct% connect
xsct% jtagterminal        ← 进入 JTAG UART 终端，按键即发（Ctrl+] 退出）

# 或 Vitis IDE：菜单 Xilinx → Launch Serial Terminal，选择 JTAG UART
```

终端里输入 `5` → 绿+红亮；输入 `7` → 三灯全亮；`0` → 全灭。

> 说明：`jtagterminal` 交互终端收发字符；程序方式可用 `readjtaguart`/`writejtaguart`
> （xsct 命令，可脚本化控制 LED）。

```text
D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source mb_led/scripts/merge_elf.tcl
```

## 合并 ELF 进 bitstream（让软核上电就能跑）

`updatemem` 把 ELF 的 BRAM 初始化数据合并进 bitstream，再重新生成 flash 镜像。
**这步之后** `dist/mb_led.bit / .bin` 就自带软核程序，烧录/下载后 LED 直接闪烁，
不再需要单独 `dow`。

## 下载运行

1. **烧 flash（软核程序已内嵌）**：
   `vivado -mode batch -source dist/program_flash.tcl -tclargs mb_led.bin`
   （如果只想 JTAG 调试：Program Device 选 `dist/mb_led.bit` 即可立即运行）
2. 断电重启（MODE=SPI），MicroBlaze 启动并控制 LED 闪烁
   （三灯全亮 → 全灭 → G+R，循环，见 `src/main.c`）。

> 如果用未合并的 bit/bin（仅硬件），需要再经 xsct 下载程序：
> ```tcl
> connect
> targets -set -filter {name =~ "*MicroBlaze*"}
> rst -processor
> dow dist/mb_led.elf
> con
> ```

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

# 合并 ELF 进 bit/bin（上电自跑）
vivado -mode batch -source mb_led/scripts/merge_elf.tcl

# 烧录 / 串口终端
vivado -mode batch -source dist/program_flash.tcl -tclargs mb_led.bin
xsct -> connect -> jtagterminal    （输入 0~7 / G / Y / R 控制 LED）

# 调试下载（xsdb）
connect / targets / rst -processor / dow dist/mb_led.elf / con
```