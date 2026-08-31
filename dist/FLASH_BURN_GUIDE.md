# MemBlaze 板卡 SPI Flash 烧录指南

> 适用器件：**xc7k325tffg900-2**（MemBlaze 板卡）
> 板载 flash：**Micron N25Q256A13EF804F**（N25Q256A，256 Mb = 32 MB，3.3 V，SPI NOR）
> 适用镜像：`dist/<工程名>.bin`（SPIx4 接口，由对应工程的 `.bit` 转换，数据约 11 MB，起始地址 0x0）
> 维护说明：每新增一个 FPGA 工程，产物按工程名区分：`dist/<工程名>.bit / .ltx / .bin`。
> 本目录（`dist/`）自包含：烧录文件（bin）+ 一键烧录脚本（program_flash.tcl）+ 本指南，
> 仅下载 `dist/` 即可完成烧录；文中的 `.tcl` 脚本命令需在完整仓库中执行。

---

## 0. 速览

```text
烧录（推荐，一键）:
    vivado -mode batch -source dist/program_flash.tcl

烧录完成 -> 断电重启 -> 板卡从 SPI flash 上电自启动
（本 demo 上电后 3 个 LED 全灭，VIO 初值均为 0）
```

---

## 1. 背景与前提

- 板卡从 **SPI flash（SPIx4 模式）** 上电自配置。依据板卡参考约束 `ddr.xdc`：
  `CONFIG_MODE SPIx4`、`BITSTREAM.CONFIG.SPI_BUSWIDTH 4`、`CONFIGRATE 66`。
- **板载 flash 已确认：Micron N25Q256A13EF804F**
  - 型号解读：`N25Q`（SPI NOR 家族）`256`（256 Mb）`A`（产品代）`13`（3.3 V 供电）
    `E`（工业级温度 -40~+85 °C）`F804`（封装/速度等级，以 datasheet 为准）
  - 容量 **256 Mb = 32 MB**；标准 SPI（1-1-1 / 1-1-4 模式）
  - Vivado Hardware Manager 中的器件名（cfgmem part）：**`mt25ql256-spi-x1_x2_x4`**
    （Micron 已将 N25Q 系列更名 MT25Q；Vivado 2024.2 中 256Mb 对应条目为
    `mt25ql256-spi-x1_x2_x4` = 3.3 V、`mt25qu256-spi-x1_x2_x4` = 1.8 V。
    旧版 Vivado 名为 `n25q256-3.3v-spi-x1_x2_x4`，以本机 `get_cfgmem_parts` 查询结果为准）
- `dist/<工程名>.bin` 由 `led_demo/scripts/create_project.tcl` **一步生成**（写位流后自动
  `write_cfgmem -format bin -interface SPIx4`），镜像已**压缩**（`BITSTREAM.GENERAL.COMPRESS TRUE`），
  配置时钟 **CONFIGRATE 50**（之前 66 MHz 太高会导致烧录/上电异常，已改 50），
  位于 32 MB flash 的 **0x0** 起始，远小于 16 MB 地址边界，无需 4 字节寻址，直接烧录即可。
- ⚠️ `.bin`、`.bit`、`.ltx` 必须来自**同一次编译**，混合使用会导致探针不匹配或功能不一致。

---

## 2. 方法一（推荐）：一键 Tcl 烧录脚本 `dist/program_flash.tcl`

脚本已生成在 `dist/` 目录，默认自动定位同目录下的 `led_demo.bin`，无需手改路径；
**也可以把 bin 文件名作为命令行参数传入**：

```text
# 无窗口批处理（推荐，已在实机验证通过）
vivado -mode batch -source dist/program_flash.tcl                    ;# 默认 led_demo.bin
vivado -mode batch -source dist/program_flash.tcl -tclargs mb_led.bin      ;# 指定镜像（文件名）
vivado -mode batch -source dist/program_flash.tcl -tclargs D:/x/y.bin       ;# 或完整路径

# 或在 Vivado GUI 的 Hardware Manager -> Tcl Console 中：
source dist/program_flash.tcl
```

脚本默认流程（**本板已实测通过**）：

```text
连接 JTAG（扫描出器件型号）
 -> 按型号自动定位 SPI 网桥 bit：<Vivado安装>/data/xicom/cfgmem/bitfile/
    spi_<器件型号>_pullnone.bit（如 spi_xc7k325t_pullnone.bit）——日志应出现
    "design has 1 SPI core(s)"
 -> 绑定 cfgmem（mt25ql256-spi-x1_x2_x4）
 -> 擦除 -> 空白检查 -> 编程 -> 校验（全程约 8~9 分钟）
 -> 断电重启，MODE=SPI 时从 flash 自举
```

> **关键机制（已实测验证）**：该板 SPI flash 接在 FPGA 的**用户 IO**上，Vivado 通过
> 先加载官方预置的 **SPI 网桥 bit** 来访问 flash。
> **为什么不需要解压**：这些网桥 bit 并不以真实文件存在，而是打包在
> `<Vivado>/data/xicom/cfgmem/bitfile.zip` 里，Vivado 把 `.../bitfile/spi_<part>_pullnone.bit`
> 当作**虚拟路径**直接流式读取对应条目（实测：磁盘上无该文件也能加载成功；
> 用 `file exists` 查会是 false，属正常）。脚本直接传递虚拟路径即可，无需解压。
> 网桥 bit 的 `_pullnone` 与烧录属性 `PROGRAM.UNUSED_PIN_TERMINATION {pull-none}` 对应
> （若改 pull-up 需用 `spi_<part>_pullup.bit`）。

可选变量（按需 `set`，普通 Tcl 变量或环境变量均可）：

| 变量 | 作用 | 示例 |
|---|---|---|
| `BIN` | 换用其它 bin | `set BIN D:/x/another.bin` |
| `DESIGN_BIT` | 手动指定网桥 bit（一般不需要） | `set DESIGN_BIT D:/x/spi_xc7k325t_pullnone.bit` |
| `FLASH_PART` | 换用其它 flash | `set FLASH_PART mt25ql256-spi-x1_x2_x4` |
| `TARGET` | JTAG 链上有多个目标时指定 | `set TARGET */xilinx_tcf/Digilent/1234...A` |
| `JTAG_FREQ` | 降低 JTAG 时钟（信号完整性） | `set JTAG_FREQ 6000000` |
| `ONLY_VERIFY` | 只校验不烧写（产线复查） | `set ONLY_VERIFY 1` |

注意事项：
- 脚本通用：网桥 bit 路径按 JTAG 扫描出的器件型号自动生成，换板/换 Vivado 版本无需修改；
- 若 JTAG 链上还有其它器件需要旁路，先用 `connect_hw_target -disable_targets ...` 屏蔽或
  设置 `PARTS.JTAGCHAIN.BYPASS`，再运行本脚本；
- 烧录时保持板卡供电稳定，过程中不要断电/断开 JTAG。

---

## 3. 方法二：Vivado Hardware Manager 图形界面

1. 打开 **Vivado** → 左侧 **Hardware Manager** → **Open Target** → 连接 JTAG。
2. 设备树右键 FPGA 器件 → **Add Configuration Memory Device**。
3. 搜索并选择 **`mt25ql256-spi-x1_x2_x4`**（对应板载 N25Q256A13EF804F）→ **OK**。
4. 烧录窗口：
   - **Assign Configuration File** → 选择 `dist/<工程名>.bin`；
   - 勾选 **Erase**（必选）、建议勾选 **Blank Check**、**Program**、**Verify**；
5. 点击 **OK**：擦除 → 空白检查 → 编程 → 校验；状态栏 `Verify successful` 即成功。
6. 断电重启，板卡从 SPI flash 自举。

> 图形界面烧录后如需再次 JTAG 在线调试，只需 **Program Device** 选 `.bit`（不要覆盖 flash）。

---

## 4. 方法三：独立 SPI flash 编程器

适用于无 Vivado 环境或流水线产测：

1. 编程器（RT809H、CH341A 等）读出芯片 ID，确认与 **N25Q256A（3.3 V）** 一致；
2. 将 `dist/<工程名>.bin` 按**地址 0x0**、**标准 SPI（1-1-4 模式）** 写入（芯片需支持 3.3 V）；
3. 写入后 **Verify**；装回板卡（烧录座/飞线方案则拆除），上电验证。

---

## 5. 常见问题（FAQ）

| 现象 | 可能原因与处理 |
|---|---|
| 找不到/选不对 flash | 确认使用 Vivado 器件名 **`mt25ql256-spi-x1_x2_x4`**（对应 N25Q256A13EF804F）；勿选 1.8 V 版本（mt25qu256-*） |
| Verify 失败 | flash 型号/电压选错、接触不良 → 核对丝印（N25Q256A13EF804F），更换匹配型号重试 |
| 烧录超时/中断 | JTAG 线接触不良或速率过高 → 确认 JTAG 链（TDO_0=G10、TDI_0=H10、TMS_0=F10、TCK_0=E10），必要时降低 JTAG 频率 |
| 烧录后上电不启动 | ① MODE 引脚（M[2:0]）未配置为 SPIx4；② flash 内仍有旧镜像（先 Erase）；③ 镜像地址不是 0x0 |
| hw_vio 看不到探针 | `.ltx` 与 `.bit` 不是同一编译产物 → 使用 `dist/` 同名的 `.bit/.ltx` 配对 |
| 想恢复 JTAG 优先 | 上电时短接相应配置跳线强制 JTAG 模式，或重新烧录正确镜像 |
| 产物被覆盖 | 严格遵守命名约定 `dist/<工程名>.bit/.ltx/.bin`，每工程一套，勿混用 |

### 5.1 `program_hw_cfgmem` 报错：`Flash Programming Unsuccessful: Failure to set flash parameters`

7 系列通过 JTAG 间接烧录 SPI flash 时的典型错误，出现时机是 `program_hw_cfgmem` 执行阶段
（此前 cfgmem 绑定、文件加载都已成功）。

**本板最终判据（已于实机验证）**：完整日志里必须出现 “design has **1 SPI core(s)**”，
这是通过 Vivado 官方预置 **SPI 网桥 bit**（`data/xicom/cfgmem/bitfile/spi_<part>_pullnone.bit`，
脚本已按扫描器件自动定位/解压/加载）访问用户 IO 上的 flash。若显示 “1 VIO core(s)”
或根本没有 core 信息（例如误用普通工程 bit 做网桥），必报此错。
已实测排除：器件名（mt25ql256 / s25fl256s 同错）、JTAG 频率（6/15/30MHz 同错）、
bin 容量（16/32MB 同错）、ADDRESS_RANGE（use_file 同错）。

| 排查项 | 操作 |
|---|---|
| ① **必须有 SPI 网桥 bit（本板根因）** | 日志需出现 `1 SPI core(s)`。脚本会自动从 `<Vivado>/data/xicom/cfgmem/bitfile.zip` 解出 `spi_<part>_pullnone.bit` 使用；若失败，检查解压目标目录是否可写，或用 `set DESIGN_BIT <path>` 手动指定 |
| ② JTAG 时钟过高 | `set JTAG_FREQ 6000000`（仍不行 3000000）后重跑 |
| ③ 器件名与硅片不匹配 | GUI **Add Configuration Memory Device** 核对 `mt25ql256-spi-x1_x2_x4`；芯片 3.3 V（丝印含 `13E`），勿用 1.8 V 的 `mt25qu256-*` |
| ④ flash 供电/电平 | flash 3.3 V 电源正常；VIO 与 FPGA 侧电平一致 |
| ⑤ WP#/HOLD# 引脚 | **WP#（写保护）须上拉 VCC**、HOLD# 上拉（或按原理图处理），排除浮空/接地 |
| ⑥ 接触与干扰 | 插紧 JTAG 线（TDO G10 / TDI H10 / TMS F10 / TCK E10），关掉其它占用 JTAG 的程序 |

> 快速再试命令：
> ```tcl
> set JTAG_FREQ 6000000
> source dist/program_flash.tcl
> ```

---

## 6. 常见操作速查

```text
# 1) 一键烧录 SPI flash（推荐；默认 led_demo.bin，可用 -tclargs 指定其它镜像）
vivado -mode batch -source dist/program_flash.tcl
vivado -mode batch -source dist/program_flash.tcl -tclargs mb_led.bin

# 2) 一键重新编译并发布 bit/ltx/bin（完整仓库，一条命令搞定）
vivado -mode batch -source led_demo/scripts/create_project.tcl

# 3) JTAG 在线调试（不烧 flash）
#    Hardware Manager -> Program Device -> dist/<工程名>.bit (+ 勾选同名 .ltx)
#    hw_vio 窗口 vio_0: probe_out0/1/2 -> LED_G/LED_Y/LED_R

# 4) 烧 flash -> 断电重启 -> 上电自运行
```