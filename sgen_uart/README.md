# MemBlaze FPGA (xc7k325tffg900-2) — sgen_uart：波形发生器 + 软核回传可视化

## 链路

```
50MHz ──clk_wiz──> 100 MHz（MicroBlaze/AXI/FIFO/DMA）
              └──> 400 MHz（波形发生器）
wave_gen(400M, 正弦/斜坡, 16bit) ─写─> wbuf(双口BRAM 1024×16)
   └─reader(100M) ─AXIS(32bit)→ axis_data_fifo(100M) ─AXIS→ AXI DMA S2MM
        └─MM─> 采集BRAM(axi_bram_ctrl 16KB) ─读─> MicroBlaze ─JTAG UART─> PC
```

- 波形：正弦（32 点查表）/ 斜坡，1024 点、16-bit，由 **400 MHz** 引擎写入双口 BRAM
- 回传：BRAM → FIFO → **AXI DMA S2MM**（100 MHz）→ 采集 BRAM → 软核读取
- 上位机：**JTAG UART**（MDM 内置虚拟串口）输出 `index,value` CSV → Python 绘图

## 构建（一条命令）

```text
D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source sgen_uart\scripts\create_project.tcl
```

产出：`dist/sgen_uart.bit/.bin` + `sgen_uart/sgen_uart.xsa`

## 软件构建 + 合并

```text
D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat sgen_uart\scripts\build_elf.tcl
D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source sgen_uart\scripts\merge_elf.tcl
```

## 烧录（上电自跑）

```text
D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source dist\program_flash.tcl -tclargs sgen_uart.bin
```

## 与上位机交互（可视化）

### 方式 A：一条命令自动捕获（推荐）

```text
D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat sgen_uart\tools\capture_uart.tcl R   ;# R=ramp, S=sine
python sgen_uart/tools/plot_csv.py sgen_uart/tools/out/capture.csv
```

脚本会：连接 JTAG → 自动选择 MicroBlaze 目标 → 向 MDM 的 UART 收寄存地址（0x41400004）写命令字符 →
软核生成并回传 → `readjtaguart` 捕获 CSV 到 `sgen_uart/tools/out/capture.csv` → Python(matplotlib) 画波形。

> 若脚本提示 “no MicroBlaze/JTAG-UART target selected” 或
> “did not expose a JTAG-UART target”：该 xsct 环境未枚举出带 UART 的目标，
> 请改用 **Vitis IDE → Serial Terminal（JTAG UART）** 触发 `S`/`R` 并把回显的
> `index,value` 行保存为 CSV 后再 plot（README “方式 B” 所述做法）。

### 方式 B：手动终端

```text
xsct.bat
xsct% connect
xsct% jtagterminal        ← 输入 S / R 触发一轮；终端内即显示 CSV
```

## 地址/寄存器（xparameters 为准）

| 外设 | 基址 | 说明 |
|---|---|---|
| axi_gpio | 0x4000_0000 | ch1 输出 ctrl：bit0=en, bit1=sel, bit2=start, bit3=rd_en；ch2 输入 sts：bit0=wave_done, bit1=rd_done |
| axi_dma (S_AXI_LITE) | 0x4001_0000 | S2MM 简单模式 |
| MDM UART | 0x4140_0000 | JTAG 虚拟串口（0x4 = 主机→软核 RX） |
| 采集 BRAM | 见 xparameters | 32-bit/字，每字低 16 位为一个样本 |

## 软件命令

| 命令 | 行为 |
|---|---|
| `S` | 生成正弦（256 点，CPU 路径）→ JTAG UART 上传 CSV |
| `R` | 生成斜坡 → JTAG UART 上传 CSV |
| `h` | 帮助 |

> **当前交付路径**：固件在 MB 本地内存（LMB @0x8000）生成波形并逐行
> `index,value` 上传到 JTAG UART（已验证：LMB 数据可由 xsdb `mrd 0x8000`
> 读回、CSV 可被终端捕获后 matplotlib 绘图）。
> **待查条目（已实证）**：`axi_bram_ctrl`（采集 BRAM）数据通路在本机工具链
> 下不可用——mwr/mrd/固件读写在所有端口、参数、段地址（0xC0000000 与
> 0x40020000）组合下读回恒为 0x8（GPIO/MDM 寄存器读写正常，可排除互连）；
> `wave_gen`(400M) 的 done 也未见（cts 级问题待板侧硬件验证）。

## 排错

- **先确认软核在跑**：xsct → MicroBlaze 目标 → `rrd pc`（capture_uart.tcl 会打印），
  有值/在变即软核执行中。
- **波形数据可验证**（不经 UART）：
  `mrd -size w 0x00008000 256` → 读到 LMB 内正弦（0→3212→6393…）。
- **JTAG UART 上传**：256 行 CSV 上传较慢（每字符需 host 读走），
  `readjtaguart` 捕获窗口建议 ≥ 30 s；若 xsct 报 "Target doesn't support Jtag
  Uart" 或始终为空，请用 Vitis IDE 的 Serial Terminal（JTAG UART）观察。
- **数据通路（RTL）验证**：`wave_gen → wbuf → reader` 行为仿真已通过
  （0×32 → 3212 → 6393 → …）。
- 400 MHz 时钟：clk_wiz 自动取 VCO=1200（50MHz×24），输出 400=1200/3、100=1200/12
- 软核未跑/无输出：确认用**带 ELF 的合并 bit/bin**（`merge_elf.tcl` 之后再烧录），
  上电会自动生成并上传一轮正弦。