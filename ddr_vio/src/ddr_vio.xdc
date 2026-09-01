##------------------------------------------------------------------------------
## MemBlaze xc7k325tffg900-2 - ddr_vio 顶层约束
## 系统时钟 D27 50MHz；DDR3 引脚见 board_reference/ddr3_72bit_converted.xdc
##------------------------------------------------------------------------------

set_property PACKAGE_PIN D27 [get_ports sys_clk_i]
set_property IOSTANDARD  LVCMOS18 [get_ports sys_clk_i]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk_i]

## ---- Bitstream 设置（与其它工程一致，实机验证过） ----
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
## D27(bank16) �� MMCM �������ſ�ר��ʱ��·�ɣ�demo ���ܣ�
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sys_clk_i_IBUF]

