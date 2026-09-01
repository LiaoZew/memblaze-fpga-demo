# MemBlaze FPGA Demo (xc7k325tffg900-2)

同一块板子上的两个 LED 控制工程，共用一套 IO 引脚约束与一键构建/烧录流程。

| 工程 | 说明 | 文档 |
|---|---|---|
| `led_demo/` | **VIO 硬核**：Vivado 内建 VIO 核在线开关 3 个 LED（HW Manager 勾选 `probe_out0/1/2`） | [led_demo/README.md](led_demo/README.md) |
| `mb_led/` | **MicroBlaze 软核**：AXI GPIO 控 LED + **JTAG UART 串口命令**（`0~7`/`G`/`Y`/`R`），ELF 已并入 bit/bin，上电自跑 | [mb_led/README.md](mb_led/README.md) |

## 目录结构（多工程并行规范）

```
board_reference/     板卡原始资料（所有工程共享，不属于任何工程）
  ├── MEMBLAZE_PINS_V2.xls   引脚总表
  ├── ddr.xdc                参考设计系统级约束（SPIx4 设置等）
  └── ddr_72bit.ucf          DDR3 72-bit 接口引脚约束
dist/                预编译产物：dist/<工程名>.bit/.ltx/.bin/.elf（互不覆盖）
docs/                规范与说明（版本控制与发布规范等）
led_demo/            VIO 硬核工程（独立目录：src/scripts/projects/README）
mb_led/              MicroBlaze 软核工程（独立目录：src/scripts/projects/README + xsa）
```

## IO 约束（两工程一致，依据 `board_reference/MEMBLAZE_PINS_V2.xls` 与 `board_reference/ddr.xdc`）

| 信号 | 引脚 | 电平 |
|---|---|---|
| `sysclk`（板载 50 MHz） | D27 | LVCMOS18 |
| `led[0]` = LED_G | R24 | LVCMOS18 |
| `led[1]` = LED_Y | T20 | LVCMOS18 |
| `led[2]` = LED_R | T21 | LVCMOS18 |

## 预编译产物（`dist/`）

- `led_demo.bit/.ltx/.bin`、`mb_led.bit/.bin/.elf`
- `program_flash.tcl`：一键烧录（`-tclargs <bin>` 指定镜像，默认 led_demo.bin），
  自动使用 Vivado 自带的 SPI 网桥 bit（zip 虚拟路径，无需解压）
- 板载 flash：**Micron N25Q256A13EF804F**（Vivado 器件名 `mt25ql256-spi-x1_x2_x4`；
  配置时钟 **CONFIGRATE 50**、COMPRESS TRUE、SPIx4）

```text
# 一条命令烧录
vivado -mode batch -source dist/program_flash.tcl -tclargs mb_led.bin
```

## 版本控制

- 分支策略 / Tag 规范 / 发版步骤见 [docs/版本控制与发布规范.md](docs/版本控制与发布规范.md)
- 当前版本：`v1.0.1`

## 快速链接

- 构建：`vivado -mode batch -source <工程>/scripts/create_project.tcl`
- 软核程序（mb_led）：`xsct.bat mb_led/scripts/build_elf.tcl` → `vivado -mode batch -source mb_led/scripts/merge_elf.tcl`
- 调试下载：xsct → `connect` → `jtagterminal`（输入 `0~7` 控制 LED）