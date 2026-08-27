# 预编译产物（Pre-built distribution artifacts）

无需重新编译，可直接烧录到 MemBlaze 板（xc7k325tffg900-2）使用。

**命名约定**：每工程一套产物，以工程名区分：`dist/<工程名>.bit / .ltx / .bin`。
本工程：**memblaze_vio**。烧录 flash 的完整步骤见本目录 [`FLASH_BURN_GUIDE.md`](FLASH_BURN_GUIDE.md)。

| 文件 | 用途 |
|---|---|
| `memblaze_vio.bit` | JTAG 在线下载。Vivado **Hardware Manager → Program Device** 选择此文件 |
| `memblaze_vio.ltx` | VIO 调试探针文件。Program 后关联此 `.ltx`（Hardware Manager 自动提示），打开 **hw_vio** 窗口即可看到 `vio_0` 的三个输出探针 `probe_out0/1/2`，分别对应 **LED_G(R24) / LED_Y(T20) / LED_R(T21)** |
| `memblaze_vio.bin` | SPIx4 配置镜像（约 11 MB，未压缩）。板载 flash 为 **Micron N25Q256A13EF804F（32 MB）**，写入其 0x0 起始地址，上电自启动；Vivado 器件名 `mt25ql256-spi-x1_x2_x4`（N25Q 系列已更名 MT25Q） |
| `program_flash.tcl` | 一键烧录脚本（推荐）：连接 JTAG → 擦除 → 空白检查 → 编程 → 校验，自动使用同目录 `memblaze_vio.bin` |
| `FLASH_BURN_GUIDE.md` | SPI flash 烧录完整指南（GUI / 脚本 / 独立编程器三种方法 + FAQ） |

## 快速开始

**A. 烧录 flash（上电自启动，推荐）**

```
vivado -mode batch -source program_flash.tcl
# 或 Hardware Manager -> Tcl Console -> source program_flash.tcl
# 完成后断电重启，板卡从 SPI flash 自举
```

**B. JTAG 在线调试（不烧 flash）**

```
Hardware Manager
 ├─ Open Target
 ├─ Program Device  ->  memblaze_vio.bit   (勾选同一目录的 .ltx)
 └─ hw_vio 窗口 vio_0
      probe_out0  <->  LED_G
      probe_out1  <->  LED_Y
      probe_out2  <->  LED_R
```

勾选 `probe_outx` 点亮对应 LED，取消则熄灭。

## 重新生成

```
# bit / ltx（自动发布到 dist/）
vivado -mode batch -source memblaze_vio/scripts/create_project.tcl
# bin（SPIx4 flash 镜像）
vivado -mode batch -source memblaze_vio/scripts/gen_flash_bin.tcl
```

> 注意：`.bit` 与 `.ltx` 必须来自同一次编译，否则 Hardware Manager 会提示探针不匹配。
> 所有产物与源码同 commit，可追溯。