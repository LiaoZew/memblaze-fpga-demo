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
- `dist/<工程名>.bin` 由 `memblaze_vio/scripts/gen_flash_bin.tcl` 生成
  （`write_cfgmem -format bin -interface SPIx4`），镜像为**未压缩** bitstream
  （`BITSTREAM.GENERAL.COMPRESS FALSE`），数据约 11 MB，位于 32 MB flash 的 **0x0** 起始，
  远小于 16 MB 地址边界，无需 4 字节寻址，直接烧录即可。
- ⚠️ `.bin`、`.bit`、`.ltx` 必须来自**同一次编译**，混合使用会导致探针不匹配或功能不一致。

---

## 2. 方法一（推荐）：一键 Tcl 烧录脚本 `dist/program_flash.tcl`

脚本已生成在 `dist/` 目录，自动定位同目录下的 `memblaze_vio.bin`，无需手改路径：

```text
# 无窗口批处理
vivado -mode batch -source dist/program_flash.tcl

# 或在 Vivado GUI 的 Hardware Manager -> Tcl Console 中：
source dist/program_flash.tcl
```

脚本默认流程：**连接 JTAG → 绑定 cfgmem（mt25ql256-spi-x1_x2_x4）→ 擦除 → 空白检查 → 编程 → 校验**。

可选环境变量（按需 `set`）：

| 变量 | 作用 | 示例 |
|---|---|---|
| `BIN` | 换用其它 bin | `set BIN D:/x/another.bin` |
| `FLASH_PART` | 换用其它 flash | `set FLASH_PART mt25ql256-spi-x1_x2_x4` |
| `TARGET` | JTAG 链上有多个目标时指定 | `set TARGET */xilinx_tcf/Digilent/1234...A` |
| `JTAG_FREQ` | 降低 JTAG 时钟（信号完整性，见 5.1） | `set JTAG_FREQ 6000000` |
| `ONLY_VERIFY` | 只校验不烧写（产线复查） | `set ONLY_VERIFY 1` |

注意事项：
- 若 JTAG 链上还有其它器件需要旁路，先用 `connect_hw_target -disable_targets ...` 屏蔽或
  设置 `PARTS.JTAGCHAIN.BYPASS`，再运行本脚本。
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
（此前 cfgmem 绑定、文件加载都已成功）。按下面的优先级排查：

| 排查项 | 操作 |
|---|---|
| ① JTAG 时钟过高（最常见） | 降低 JTAG 频率后重跑：`set JTAG_FREQ 6000000`（仍不行用 3000000）再 `source dist/program_flash.tcl` |
| ② FPGA 未处于未配置态 | 间接烧录要求 **DONE=0**（日志中应出现 `Device ... is not programmed (DONE status = 0)`）。若提示 DONE=1，先对器件执行 `program_hw_devices -clear` 或断电重上电 |
| ③ 器件名与硅片不匹配 | 在 GUI 用 **Add Configuration Memory Device** 手工核对列表中 `mt25ql256-spi-x1_x2_x4` 是否存在；确认芯片是 3.3 V（丝印含 `13E`），勿用 1.8 V 的 `mt25qu256-*` |
| ④ flash 供电/电平 | 确认 flash 的 3.3 V 电源、VIO 与 FPGA bank-0 配置电压一致（CFGBVS）；用万用表确认 CCLK / FCS_B / D[3:0] 到 flash 的连接与上拉电阻正常 |
| ⑤ WP#/HOLD# 引脚 | 写保护失效会导致参数写不进去：确认 **WP#（写保护）上拉到 VCC**、HOLD# 上拉（或按板卡原理图处理），排除浮空/接地 |
| ⑥ 接触与干扰 | 更换/插紧 JTAG 线与排针（TDO G10 / TDI H10 / TMS F10 / TCK E10），远离干扰源；拔掉其它 JTAG 链设备 |
| ⑦ 换 GUI 流验证 | 用方法二（GUI 图形界面）跑一次同样的擦除/编程/校验：若 GUI 成功而脚本失败，多半是脚本属性差异，把 GUI 生成的 Tcl 日志发回来对照 |

> 快速再试命令（保持 GUI 连接状态）：
> ```tcl
> set JTAG_FREQ 6000000
> source dist/program_flash.tcl
> ```

---

## 6. 常见操作速查

```text
# 1) 一键烧录 SPI flash（推荐）
vivado -mode batch -source dist/program_flash.tcl

# 2) 重新编译并发布 bit/ltx（完整仓库）
vivado -mode batch -source memblaze_vio/scripts/create_project.tcl

# 3) 重新生成 SPIx4 flash 镜像并发布 bin（完整仓库）
vivado -mode batch -source memblaze_vio/scripts/gen_flash_bin.tcl

# 4) JTAG 在线调试（不烧 flash）
#    Hardware Manager -> Program Device -> dist/<工程名>.bit (+ 勾选同名 .ltx)
#    hw_vio 窗口 vio_0: probe_out0/1/2 -> LED_G/LED_Y/LED_R

# 5) 烧 flash -> 断电重启 -> 上电自运行
```