##------------------------------------------------------------------------------
## MemBlaze xc7k325tffg900-2 - MicroBlaze LED demo constraints
## Same IO as the VIO demo (MEMBLAZE_PINS_V2.xls / ddr.xdc):
##   sysclk  D27  LVCMOS18  50 MHz  (board CLCK)
##   led[0]  R24  LVCMOS18  LED_G (green)
##   led[1]  T20  LVCMOS18  LED_Y (yellow)
##   led[2]  T21  LVCMOS18  LED_R (red)
##------------------------------------------------------------------------------

set_property PACKAGE_PIN D27 [get_ports sysclk]
set_property IOSTANDARD  LVCMOS18 [get_ports sysclk]
create_clock -period 20.000 -name sysclk [get_ports sysclk]

set_property PACKAGE_PIN R24 [get_ports {led[0]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {led[0]}]

set_property PACKAGE_PIN T20 [get_ports {led[1]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {led[1]}]

set_property PACKAGE_PIN T21 [get_ports {led[2]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {led[2]}]

## ---- Bitstream settings (same as the working led_demo) ----
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]