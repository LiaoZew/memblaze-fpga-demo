#==============================================================================
# MemBlaze xc7k325tffg900-2 - SPI flash programming script (Vivado)
#
# Flash on the board: Micron N25Q256A13EF804F (256 Mb = 32 MB, 3.3 V, SPI)
#   Vivado cfgmem part (2024.2): mt25ql256-spi-x1_x2_x4
#   (Micron renamed N25Q -> MT25Q; older Vivado: n25q256-3.3v-spi-x1_x2_x4)
#
# IMPORTANT - proven flow on this board (verified on hardware):
#   The SPI flash is on USER I/O pins, so it can ONLY be accessed through a
#   PROGRAMMED design that exposes an SPI core to the JTAG debug chain.
#   Vivado reports that as "design has 1 SPI core(s)". The flow:
#      1. program the device with a bitstream whose design contains an SPI
#         core (e.g. another project with an SPI controller on this board)
#      2. associate the matching .ltx probes file
#      3. program the flash through the design's SPI bridge
#   A design WITHOUT an SPI core (e.g. this VIO demo) CANNOT be used for
#   flash programming ("Failure to set flash parameters").
#
#   In the Vivado GUI, open the SPI-core project first so that
#   PROGRAM.HW_CFGMEM_BITFILE / PROBES.FILE are populated automatically;
#   this script uses them when present. In batch mode, pass DESIGN_BIT.
#
# Image: <this script's folder>/memblaze_vio.bin
#        (SPIx4, uncompressed bitstream ~11 MB, starting at flash address 0x0)
#
# Usage:
#   Option A - batch (no GUI):
#       set DESIGN_BIT D:/x/design_with_spi.bit      (design that has an SPI core)
#       vivado -mode batch -source program_flash.tcl
#   Option B - Vivado GUI, Hardware Manager (recommended):
#       open the SPI-core project -> connect target -> Tcl Console:
#       source program_flash.tcl
#
# Optional overrides (set BEFORE sourcing; env-var or plain Tcl var):
#   set DESIGN_BIT D:/x/design.bit       ;# bitstream WITH an SPI core
#   set BIN        D:/x/another.bin      ;# use a different .bin
#   set FLASH_PART mt25ql256-spi-x1_x2_x4 ;# different cfgmem part
#   set TARGET     */xilinx_tcf/Digilent/2102...A ;# pick the JTAG target
#   set JTAG_FREQ  6000000               ;# lower JTAG clock
#   set ONLY_VERIFY 1                    ;# skip erase/program, verify only
#==============================================================================

# ---- configuration -----------------------------------------------------------
proc getopt {name default} {
    if {[info exists ::env($name)]} { return $::env($name) }
    if {[info exists ::$name]}      { return [set ::$name] }
    return $default
}

set script_dir [file dirname [file normalize [info script]]]
set bin_file    [getopt BIN        [file join $script_dir memblaze_vio.bin]]
set design_bit  [getopt DESIGN_BIT ""]
set flash_part  [getopt FLASH_PART {mt25ql256-spi-x1_x2_x4}]
set target      [getopt TARGET     {}]
set jtag_freq   [getopt JTAG_FREQ  {}]
set only_verify [expr {[getopt ONLY_VERIFY 0] eq "1"}]

if {![file exists $bin_file]} { error "Image file not found: $bin_file" }

# locate the cfgmem part; give useful candidates if the name is wrong
set part_obj [lindex [get_cfgmem_parts $flash_part] 0]
if {$part_obj eq ""} {
    set candidates [lsort -unique [get_cfgmem_parts {*256*}]]
    puts "ERROR: no cfgmem part matches '$flash_part'."
    puts "Try one of these 256 Mb SPI parts:"
    puts [join $candidates "\n"]
    error "cfgmem part '$flash_part' not found"
}

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

if {$jtag_freq ne ""} {
    catch {set_property PARAM.FREQUENCY $jtag_freq [current_hw_target]}
    puts "JTAG frequency set to $jtag_freq Hz"
}

# ---- resolve the design bit (must contain an SPI core for flash access) ------
if {$design_bit eq ""} {
    set design_bit [get_property PROGRAM.HW_CFGMEM_BITFILE $hw_dev]
}
if {$design_bit eq ""} {
    # fall back to the demo bit - flashes a clear warning that it has no SPI core
    set design_bit [file join $script_dir memblaze_vio.bit]
}
if {![file exists $design_bit]} { error "Design bitstream not found: $design_bit" }
puts "design bit: $design_bit"

# associate the probes file (same folder as the bit, same base name) if present
set ltx_file [string map {.bit .ltx} $design_bit]
if {[file exists $ltx_file]} {
    set_property PROBES.FILE $ltx_file $hw_dev
    puts "probes file: $ltx_file"
}

# ---- bind the configuration memory device (reuse if already bound) -----------
set cfgmem ""
catch {set cfgmem [current_hw_cfgmem]}
if {$cfgmem eq ""} {
    create_hw_cfgmem -hw_device $hw_dev $part_obj
    set cfgmem [current_hw_cfgmem]
}
puts "cfgmem: [get_property NAME $cfgmem]  ($flash_part)"

# proven property set (matches the GUI flow that succeeded)
set_property PROGRAM.FILES              [list $bin_file]   $cfgmem
set_property PROGRAM.PRM_FILE           {}                 $cfgmem
set_property PROGRAM.ADDRESS_RANGE      {use_file}         $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none}    $cfgmem
set_property PROGRAM.CHECKSUM           0                  $cfgmem

if {$only_verify} {
    set_property PROGRAM.BLANK_CHECK  1 $cfgmem
    set_property PROGRAM.ERASE        0 $cfgmem
    set_property PROGRAM.CFG_PROGRAM  0 $cfgmem
    set_property PROGRAM.VERIFY       1 $cfgmem
} else {
    set_property PROGRAM.BLANK_CHECK  1 $cfgmem
    set_property PROGRAM.ERASE        1 $cfgmem
    set_property PROGRAM.CFG_PROGRAM  1 $cfgmem
    set_property PROGRAM.VERIFY       1 $cfgmem
}

# ---- program the device (SPI-bridge design), THEN program the flash ----------
puts "--- program device with the SPI-core design ---"
create_hw_bitstream -hw_device $hw_dev $design_bit
program_hw_devices $hw_dev
refresh_hw_device -update_hw_probes true $hw_dev

puts "--- program_hw_cfgmem (erase / blank check / program / verify) ---"
if {[catch {program_hw_cfgmem -hw_cfgmem $cfgmem} err]} {
    puts "----------------------------------------------------------------------"
    puts "ERROR: flash programming failed: $err"
    puts "Troubleshooting (details in FLASH_BURN_GUIDE.md, section 5.1):"
    puts "  1. The design bit MUST contain an SPI core - check the log for"
    puts "     'design has 1 SPI core(s)'. The VIO demo bit has NO SPI core."
    puts "  2. In the GUI: open the SPI-core project first, then source this script."
    puts "  3. Batch: set DESIGN_BIT <path to the SPI-core .bit>"
    puts "  4. Lower JTAG clock if unstable: set JTAG_FREQ 6000000"
    puts "----------------------------------------------------------------------"
    error $err
}
puts "=== Flash programming completed (erase / blank check / program / verify) ==="
puts "=== Power-cycle the board (MODE pins = SPI) - it boots from the flash. ==="