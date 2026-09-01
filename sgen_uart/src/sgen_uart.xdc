##------------------------------------------------------------------------------
## MemBlaze xc7k325tffg900-2 - sgen_uart (波形发生器 + 软核回传) 约束
## 时钟 D27 50MHz；其余接口均在 Block Design 内部，无额外引脚约束
##------------------------------------------------------------------------------

set_property PACKAGE_PIN D27 [get_ports sysclk]
set_property IOSTANDARD  LVCMOS18 [get_ports sysclk]
create_clock -period 20.000 -name sysclk [get_ports sysclk]

## ---- Bitstream 设置（与 led_demo/mb_led 一致，实机验证过） ----
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]