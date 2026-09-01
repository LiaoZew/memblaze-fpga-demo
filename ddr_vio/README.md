# MemBlaze FPGA (xc7k325tffg900-2) — ddr_vio：用 VIO 控制 DDR3 读写

纯 PL 工程：**MIG 7 Series（DDR3 72-bit）+ VIO 控制 + 简易 app 状态机**，
不涉及软核。

## 数据/控制流

```
VIO (ui_clk 域)
  probe_out0 rst[0]        -> MIG sys_rst
  probe_out1 wr_en 脉冲     -> 写一次 72bit
  probe_out2 rd_en 脉冲     -> 读一次 72bit
  probe_out3 wr_addr[26:0]  probe_out4 rd_addr[26:0]
  probe_out5 wr_data[71:0]
  probe_in0 init_calib_done   probe_in1 app_rdy   probe_in2 app_wdf_rdy
  probe_in3 rd_valid          probe_in4 rd_data[71:0]
  probe_in5 busy              probe_in6 done      probe_in7 rst echo

top -> mig_0(app 接口) -> ddr_ctrl(状态机) -> DDR3(引脚见 board_reference)
```

## 构建（两步：MIG 一次性 GUI 向导 + 一键脚本）

MIG 7 Series 的参数在 Vivado 2024.2 中**不支持 Tcl 配置**（create_ip 后锁定），
需做一次性向导（其余全部自动）：

```text
1) 开 GUI：
   D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source ddr_vio\scripts\create_project.tcl
   之后项目已建好但没有 MIG —— 按提示：
   vivado.bat ddr_vio\projects\ddr_vio.xpr     （或运行 scripts\open_gui.tcl）

2) 在 GUI 的 IP Catalog 添加 MIG 7 Series（Customize IP）：
   名称 mig_0，保存目录 ddr_vio\ip
   Memory Type: DDR3    Memory Part: MT41K512M8DA-125
   72-bit，无 ECC；Speed 800 Mt/s（400MHz）；Input Clock 20000ps、Single-Ended
   引脚可选导入 ddr_vio\pins_bank.csv；不导入也行——板卡引脚最终由
   board_reference\ddr3_72bit_converted.xdc 覆盖（信号名与 MIG 顶层完全一致）

3) 重新运行脚本完成综合/实现：
   D:\xilinx\rundir3\Vivado\2024.2\bin\vivado.bat -mode batch -source ddr_vio\scripts\create_project.tcl
```

产出 `dist/ddr_vio.bit/.bin`（含 VIO；上电后直接用 Hardware Manager 操作 VIO，无软核）。

## 使用方法（Hardware Manager）

1. Program `dist/ddr_vio.bit`（或烧 bin 后接 JTAG 打开）
2. **先复位**：`probe_out0 rst=1 保持数秒后置 0`（MIG 初始化需要 >200us 复位低）
   —— 观察到 `probe_in0 init_calib_done` 变为 **1** 才可读写
3. **写**：设 `wr_addr`（如 0）、`wr_data`（如 0x1234567890ABCDEF00）；`wr_en` 置 1 再置 0（脉冲）
   —— `busy` 高一次后 `done`=1
4. **读**：设 `rd_addr`（同一地址）；`rd_en` 脉冲 → 等待 `rd_valid`=1 → `probe_in4 rd_data` 应等于刚才写入值

## 地址约定

MIG 配置 `BANK_ROW_COLUMN`（4Gb x8, 9 片 → 72bit）：
app_addr 由 MIG 自动把 {bank, row, col} 交织为 27bit，遵循部件表（2Gb/4Gb 行/列）。
简单体验读写回环时可固定用 `wr_addr = rd_addr = 0` 验证同一位置。

## 排错

- `init_calib_done` 恒 0：复位时序/时钟（D27 50M 必须正常）/引脚（bank 32/33/34 SSTL15）
- `app_rdy` 恒 0：校准未完成或 ui_clk 未起
- 读回不等于写入：检查 `rd_addr` 与 `wr_addr` 一致、等待 `rd_valid`（不要提前读 probe_in4）

## 参考文件

- 引脚约束（SSTL15/DIFF_SSTL15 + 引脚）由 `board_reference/ddr3_72bit_converted.xdc` 提供
- MIG 顶层端口名与板卡信号一一对应（dq[71:0]/dqs[8:0]/dm[8:0]/addr[15:0]/ba[2:0]...）