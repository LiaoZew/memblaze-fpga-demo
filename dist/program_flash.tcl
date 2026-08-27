#==============================================================================
# MemBlaze xc7k325tffg900-2 - SPI flash programming script (Vivado)
#
# Flash on the board: Micron N25Q256A13EF804F
#   - N25Q256A  256 Mb = 32 MB, 3.3 V, SPI NOR, standard SPI (1-1-4)
#   - NOTE: Micron renamed N25Q -> MT25Q. In Vivado 2024.2 the cfgmem part is
#     mt25ql256-spi-x1_x2_x4   (mt25ql256 = 3.3 V; mt25qu256 = 1.8 V)
#     (Older Vivado versions name it n25q256-3.3v-spi-x1_x2_x4)
#
# Image: <this script's folder>/memblaze_vio.bin
#        (SPIx4, uncompressed bitstream ~11 MB, starting at flash address 0x0)
#
# Usage:
#   Option A - batch (no GUI):
#       vivado -mode batch -source program_flash.tcl
#   Option B - Vivado GUI, Hardware Manager:
#       Tcl Console -> source program_flash.tcl
#
# Optional overrides (set BEFORE sourcing; both env-var and plain Tcl var work):
#   set BIN        D:/x/another.bin       ;# use a different .bin
#   set FLASH_PART mt25ql256-spi-x1_x2_x4 ;# different cfgmem part
#   set TARGET     */xilinx_tcf/Digilent/2102...A ;# pick the JTAG target
#   set ONLY_VERIFY 1                     ;# skip erase/program, verify only
#==============================================================================

# ---- configuration (override: env var or plain Tcl variable) ----------------
proc getopt {name default} {
    if {[info exists ::env($name)]} { return $::env($name) }
    if {[info exists ::$name]}      { return [set ::$name] }
    return $default
}

set script_dir [file dirname [file normalize [info script]]]
set bin_file    [getopt BIN        [file join $script_dir memblaze_vio.bin]]
set flash_part  [getopt FLASH_PART {mt25ql256-spi-x1_x2_x4}]
set target      [getopt TARGET     {}]
set only_verify [expr {[getopt ONLY_VERIFY 0] eq "1"}]

if {![file exists $bin_file]} {
    error "Configuration file not found: $bin_file"
}

# locate the cfgmem part; give useful candidates if the name is wrong
set part_obj [lindex [get_cfgmem_parts $flash_part] 0]
if {$part_obj eq ""} {
    set candidates [lsort -unique [get_cfgmem_parts {*256*}]]
    puts "ERROR: no cfgmem part matches '$flash_part'."
    puts "Try one of these 256 Mb SPI parts:"
    puts [join $candidates "\n"]
    error "cfgmem part '$flash_part' not found"
}

puts "=================================================="
puts " SPI flash programming (Vivado)"
puts "   device  : xc7k325tffg900-2"
puts "   flash   : $flash_part"
puts "   image   : $bin_file"
puts "=================================================="

# ---- connect to the JTAG target ---------------------------------------------
open_hw_manager
connect_hw_server
if {$target ne ""} {
    open_hw_target $target
} else {
    open_hw_target
}
current_hw_device [lindex [get_hw_devices] 0]
set hw_dev [current_hw_device]
puts "target: [get_property NAME [current_hw_target]]"
puts "device: [get_property NAME $hw_dev]  (part [get_property PART $hw_dev])"
refresh_hw_device -update_hw_probes false $hw_dev

# ---- bind the configuration memory device (reuse if already bound) -----------
set cfgmem ""
catch {set cfgmem [current_hw_cfgmem]}
if {$cfgmem eq ""} {
    create_hw_cfgmem -hw_device $hw_dev $part_obj
    set cfgmem [current_hw_cfgmem]
}
puts "cfgmem: [get_property NAME $cfgmem]  ($flash_part)"

set_property PROGRAM.FILES       [list $bin_file]                               $cfgmem
set_property PROGRAM.ADDRESS_RANGE {Use flash memory address range}             $cfgmem

if {$only_verify} {
    # only verify what is currently stored in the flash
    set_property PROGRAM.ERASE        0 $cfgmem
    set_property PROGRAM.BLANK_CHECK  1 $cfgmem
    set_property PROGRAM.CFG_PROGRAM  0 $cfgmem
    set_property PROGRAM.VERIFY       1 $cfgmem
} else {
    # erase -> blank check -> program -> verify
    set_property PROGRAM.ERASE        1 $cfgmem
    set_property PROGRAM.BLANK_CHECK  1 $cfgmem
    set_property PROGRAM.CFG_PROGRAM  1 $cfgmem
    set_property PROGRAM.VERIFY       1 $cfgmem
}

# ---- program -----------------------------------------------------------------
program_hw_cfgmem $cfgmem
puts "=== Flash programming completed (erase / blank check / program / verify) ==="
puts "=== Power-cycle the board - it will now boot from the SPI flash. ==="