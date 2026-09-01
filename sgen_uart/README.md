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
| `S` | 生成正弦 → DMA 回传 → 上传 CSV |
| `R` | 生成斜坡 → DMA 回传 → 上传 CSV |
| `h` | 帮助 |

## 排错

- **先确认软核在跑**：`xsct.connect` 后选 MicroBlaze 目标，读两次 `rrd pc`
  （capture_uart.tcl 会自动打印 PC1/PC2）——**两次不同即软核正在执行**。
- **固件数据去向**：capture_uart.tcl 的 `-program` 模式会打印
  `ACQ_BRAM[0..3]` 与 `PC` 诊断；正弦正常时应为 `0,3212,6393,9512`。
  若 BRAM 非正弦（如固定 0x8），通常是板侧触发/复位时序问题，先查
  `ctrl` 位与 MDM Debug_SYS_Rst 复位路径，并在 Vitis Serial Terminal 观察 banner。
- **数据通路验证**：`wave_gen → wbuf → reader` 的行为仿真已通过（样本序列按
  32 点 LUT 展开：0×32 → 3212 → 6393 → …）。
- 400 MHz 时钟：clk_wiz 自动取 VCO=1200（50MHz×24），输出 400=1200/3、100=1200/12
- **JTAG UART 上传**：上传 1024 行经 JTAG UART 很慢（每字符需 host 读走），
  `readjtaguart` 捕获窗口建议 ≥ 30 s；若 xsct 报 "Target doesn't support Jtag
  Uart" 或始终为空，请用 Vitis IDE 的 Serial Terminal（JTAG UART）长时观察。
- 软核未跑/无输出：确认用**带 ELF 的合并 bit/bin**（`merge_elf.tcl` 之后再烧录），
  上电会自动跑一轮 sine。