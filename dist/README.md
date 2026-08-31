# 预编译产物（Pre-built distribution artifacts）

无需重新编译，可直接烧录到 MemBlaze 板（xc7k325tffg900-2）使用。

**命名约定**：每工程一套产物，以工程名区分：`dist/<工程名>.bit / .ltx / .bin`。
本工程：**led_demo**。烧录 flash 的完整步骤见本目录 [`FLASH_BURN_GUIDE.md`](FLASH_BURN_GUIDE.md)。

| 文件 | 用途 |
|---|---|
| `led_demo.bit` | JTAG 在线下载。Vivado **Hardware Manager → Program Device** 选择此文件 |
| `led_demo.ltx` | VIO 调试探针文件。Program 后关联此 `.ltx`（Hardware Manager 自动提示），打开 **hw_vio** 窗口即可看到 `vio_0` 的三个输出探针 `probe_out0/1/2`，分别对应 **LED_G(R24) / LED_Y(T20) / LED_R(T21)** |
| `led_demo.bin` | SPIx4 配置镜像（已压缩 COMPRESS TRUE、CONFIGRATE 50）。板载 flash 为 **Micron N25Q256A13EF804F（32 MB）**，写入其 0x0 起始地址，上电自启动；Vivado 器件名 `mt25ql256-spi-x1_x2_x4`（N25Q 系列已更名 MT25Q） |
| `program_flash.tcl` | 一键烧录脚本（推荐）：连接 JTAG → 擦除 → 空白检查 → 编程 → 校验，自动使用同目录 `led_demo.bin` |
| `FLASH_BURN_GUIDE.md` | SPI flash 烧录完整指南（GUI / 脚本 / 独立编程器三种方法 + FAQ） |

## MicroBlaze 工程（mb_led）产物

MicroBlaze + AXI GPIO 软核工程（见 `mb_led/README.md`）：

| 文件 | 说明 |
|---|---|
| `mb_led.bit` | MicroBlaze 硬件 bitstream，**已内嵌 ELF**（AXI GPIO 控制 3 LED，上电即运行） |
| `mb_led.bin` | SPIx4 flash 镜像，**已内嵌 ELF**（烧录后断电重启软核自动跑起来） |
| `mb_led.elf` | 软核程序源文件（standalone，LED 闪烁演示；由 `mb_led/scripts/build_elf.tcl` 编译） |
| 无 `.ltx` | MicroBlaze 调试走 MDM 专用 JTAG 口，不需要探针文件（正常） |

> 合并流程：`mb_led/scripts/merge_elf.tcl`（updatemem）把 ELF 合进 bit/bin，所以
> dist 里的 mb_led 产物**自带程序**，无需再单独下载 ELF。

## 快速开始

**A. 烧录 flash（上电自启动，推荐，已实机验证）**

```
# 默认烧 led_demo.bin；用 -tclargs 指定其它镜像（文件名或完整路径）
vivado -mode batch -source program_flash.tcl
vivado -mode batch -source program_flash.tcl -tclargs mb_led.bin
# 脚本按 JTAG 扫描到的器件型号，自动使用 Vivado 自带的 SPI 网桥 bit
# （data/xicom/cfgmem/bitfile.zip 的虚拟路径直接读取，无需解压），然后
# 完成 擦除 -> 编程 -> 校验（约 8~9 分钟），完成后断电重启即从 flash 自举
```

**B. JTAG 在线调试（不烧 flash）**

```
Hardware Manager
 ├─ Open Target
 ├─ Program Device  ->  led_demo.bit   (勾选同一目录的 .ltx)
 └─ hw_vio 窗口 vio_0
      probe_out0  <->  LED_G
      probe_out1  <->  LED_Y
      probe_out2  <->  LED_R
```

勾选 `probe_outx` 点亮对应 LED，取消则熄灭。

## 重新生成

```
# 一键重建（综合/实现/bitstream + SPIx4 bin，全部自动发布到 dist/）
vivado -mode batch -source led_demo/scripts/create_project.tcl
```

> 注意：`.bit` 与 `.ltx` 必须来自同一次编译，否则 Hardware Manager 会提示探针不匹配。
> 所有产物与源码同 commit，可追溯。