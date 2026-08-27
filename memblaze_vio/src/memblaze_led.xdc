##------------------------------------------------------------------------------
## MemBlaze xc7k325tffg900-2 - VIO LED demo constraints
## IO assignments derived from:
##   - MEMBLAZE_PINS_V2.xls (Sheet1: 时钟/CLCK/D27, LED_G/R24, LED_Y/T20, LED_R/T21)
##   - ddr.xdc reference design (sysclk=D27 LVCMOS18, init_calib_complete=R24
##     LVCMOS18, heartbeat=T20 LVCMOS18, error=T21 LVCMOS18)
##------------------------------------------------------------------------------

## ---- 50 MHz single-ended board clock (1.8 V) ----
set_property PACKAGE_PIN D27 [get_ports sysclk]
set_property IOSTANDARD  LVCMOS18 [get_ports sysclk]
create_clock -period 20.000 -name sysclk [get_ports sysclk]

## ---- Three on-board LEDs (1.8 V LVCMOS) ----
set_property PACKAGE_PIN R24 [get_ports led_g]
set_property IOSTANDARD  LVCMOS18 [get_ports led_g]

set_property PACKAGE_PIN T20 [get_ports led_y]
set_property IOSTANDARD  LVCMOS18 [get_ports led_y]

set_property PACKAGE_PIN T21 [get_ports led_r]
set_property IOSTANDARD  LVCMOS18 [get_ports led_r]

## ---- Bitstream settings copied from the board reference ddr.xdc (SPIx4 flash) ----
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]