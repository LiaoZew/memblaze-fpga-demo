# MemBlaze 板卡 SPI Flash 烧录指南

> 适用器件：**xc7k325tffg900-2**（MemBlaze 板卡）
> 适用镜像：`dist/*.bin`（由对应工程的 `.bit` 转换而来，SPIx4 接口，16 MB，起始地址 0x0）
> 维护说明：每新增一个 FPGA 工程，产物按工程名区分：`dist/<工程名>.bit / .ltx / .bin`。
> 本目录（`dist/`）自包含：烧录所需文件（bin/bit/ltx）与本指南放在一起，
> 仅下载 `dist/` 即可完成烧录；文中的 `.tcl` 脚本命令需在完整仓库中执行。

---

## 1. 背景与前提

- 板卡从 **SPI flash（SPIx4 模式）** 上电自配置。依据板卡参考约束 `ddr.xdc`：
  `CONFIG_MODE SPIx4`、`BITSTREAM.CONFIG.SPI_BUSWIDTH 4`、`CONFIGRATE 66`。
- `dist/<工程名>.bin` 由 `scripts/gen_flash_bin.tcl` 生成（`write_cfgmem -format bin -interface SPIx4`），
  镜像为**未压缩** bitstream（`BITSTREAM.GENERAL.COMPRESS FALSE`），约 11 MB，放在 flash **0x0** 起始。
- ⚠️ `.bin`、`.bit`、`.ltx` 必须来自**同一次编译**，混合使用会导致探针不匹配或功能不一致。

### 确认板载 flash 型号

烧录前请确认板上的 SPI flash 芯片（看丝印或查 BOM），常见备选（**容量 ≥ 16 MB**，3.3 V、SPI 1-1-4 模式）：

| 厂商 | 型号示例 | 容量 |
|---|---|---|
| Micron | N25Q128A13ESE40E 等 | 128 Mb = 16 MB |
| Winbond | W25Q128JV | 128 Mb = 16 MB |
| ISSI | IS25LP128 / IS25WP128 | 128 Mb = 16 MB |
| Spansion/Cypress | S25FL128S | 128 Mb = 16 MB |

> 容量更大的 flash（如 256 Mb）同样可用，镜像内容不变；Vivado 选择器件时选与板上丝印一致的型号。

---

## 2. 方法一：Vivado Hardware Manager 图形界面（推荐）

1. 打开 **Vivado** → 左侧 **Hardware Manager** → **Open Target** → 连接 JTAG（按板卡 JTAG 链配置选择连接方式）。
2. 左侧设备树右键 FPGA 器件 → **Add Configuration Memory Device**。
3. 在搜索框输入板上 flash 型号（如 `n25q128`
   、`w25q128`、`s25fl128`），选中后 **OK**。
   - 若列表无完全一致型号，选择**同容量同接口的兼容型号**（SPI、1-1-4）。
4. 弹出烧录窗口后：
   - 点击 **Assign Configuration File**，选择 `dist/<工程名>.bin`；
   - 确认 **Configuration File** 栏已加载；
   - 勾选 **Erase**（必选）、建议再勾选 **Blank Check**、**Program**、**Verify**；
5. 点击 **OK** 开始：擦除 → 空白检查 → 编程 → 校验。状态栏显示 `Verify successful` 即烧录成功。
6. 断电重启板卡，程序从 SPI flash 自举（本 demo 默认 3 个 LED 全灭，VIO 初值均为 0）。

> 图形界面烧录后如需再次 JTAG 下载调试，只需 **Program Device** 选 `.bit`，不要覆盖 flash。

---

## 3. 方法二：Tcl 批处理烧录（无窗口环境 / 自动化）

将 `PROJ` 路径替换为实际路径，在 Vivado Tcl Console 或 `vivado -mode batch -source flash_program.tcl` 中执行：

```tcl
set BIN {D:/.../dist/memblaze_vio.bin}
set FLASH_PART {n25q128-3.3v-spi-x1_x2_x4}   ;# 以板载芯片为准（n25q128 / w25q128 / s25fl128 ...）

open_hw
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
refresh_hw_device -update_hw_probes false [current_hw_device]

# 绑定 cfgmem 器件
create_hw_cfgmem -hw_device [current_hw_device] [lindex [get_cfgmem_parts $FLASH_PART] 0]
set_property PROGRAM.FILES [list $BIN] [current_hw_cfgmem]
set_property PROGRAM.BLANK_CHECK  1 [current_hw_cfgmem]
set_property PROGRAM.ERASE        1 [current_hw_cfgmem]
set_property PROGRAM.CFG_PROGRAM  1 [current_hw_cfgmem]
set_property PROGRAM.VERIFY       1 [current_hw_cfgmem]

program_hw_cfgmem [current_hw_cfgmem]
puts "=== Flash programming done & verified ==="
```

> 若 JTAG 链上还有其它器件需要旁路，加 `set_property PARTS.JTAGCHAIN.BYPASS ... ` 或使用
> `connect_hw_target -disable_targets [lindex [get_hw_targets] 0]` 后再逐一使能。

---

## 4. 方法三：独立 SPI flash 编程器

适用于无 Vivado 环境或流水线产测：

1. 用编程器（如 RT809H、CH341A 等）读出芯片 ID，确认型号；
2. 将 `dist/<工程名>.bin` 按**地址 0x0**、**标准 SPI（1-1-4 模式）** 写入；
3. 写入后 **Verify**；
4. 芯片装回板卡（若用烧录座/飞线方案则拆除），上电验证。

> 注意：编程器必须支持 3.3 V 电平芯片；镜像内容与 Vivado 生成的 `.bin` 完全一致，无需转换。

---

## 5. 常见问题（FAQ）

| 现象 | 可能原因与处理 |
|---|---|
| Verify 失败 | flash 型号选错、容量不符、电平/电压不匹配 → 核对丝印与 BOM；更换匹配型号重试 |
| 烧录后上电不启动 | ① MODE 引脚（M[2:0]）未配置为 SPIx4 模式；② flash 里还有旧镜像残留（需先 Erase）；③ 镜像地址不是 0x0 |
| JTAG 连接失败/烧录中断 | 检查 JTAG 链（TDO_0=G10、TDI_0=H10、TMS_0=F10、TCK_0=E10）；接触不良时可调低 JTAG 频率 |
| hw_vio 看不到探针 | `.ltx` 与 `.bit` 不是同一编译产物 → 用 `dist/` 同名的 `.bit/.ltx` 配对 |
| 想恢复出厂/JTAG 优先 | 上电时按住/短接相应配置跳线强制 JTAG 模式，或重新烧录正确镜像 |
| 产物被覆盖 | 严格遵守命名约定 `dist/<工程名>.bit/.ltx/.bin`，每工程一套，勿混用 |

---

## 6. 常见操作速查

```text
# 1) 重新编译并发布 bit/ltx
vivado -mode batch -source memblaze_vio/scripts/create_project.tcl

# 2) 生成 SPIx4 flash 镜像并发布 bin
vivado -mode batch -source memblaze_vio/scripts/gen_flash_bin.tcl

# 3) JTAG 在线调试（不烧 flash）
#    Hardware Manager -> Program Device -> dist/<工程名>.bit  (+ 勾选同名 .ltx)
#    hw_vio 窗口 vio_0: probe_out0/1/2 -> LED_G/LED_Y/LED_R

# 4) 烧 flash（方法一/二/三任选）-> 断电重启 -> 上电自运行
```