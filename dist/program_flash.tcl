#==============================================================================
# MemBlaze xc7k325tffg900-2 - SPI flash programming script (Vivado)
#
# Flash on the board: Micron N25Q256A13EF804F (256 Mb = 32 MB, 3.3 V, SPI)
#   Vivado cfgmem part (2024.2): mt25ql256-spi-x1_x2_x4
#
# PROVEN MECHANISM (verified on this board):
#   The SPI flash lives on user I/O pins, so Vivado programs it by first
#   loading a PREBUILT SPI-bridge bitstream into the FPGA:
#       <vivado>/data/xicom/cfgmem/bitfile/spi_<part>_pullnone.bit
#   (e.g. .../spi_xc7k325t_pullnone.bit - the name is chosen from the
#    JTAG-scanned device part; _pullnone matches
#    PROGRAM.UNUSED_PIN_TERMINATION {pull-none}).
#   NOTE: these files are NOT stored loose on disk. They live inside
#   <vivado>/data/xicom/cfgmem/bitfile.zip and are streamed from the
#   archive through a VIRTUAL path - no extraction is needed and `file
#   exists` will report false for them. (Verified on hardware.)
#   Log then shows: "design has 1 SPI core(s)", and program_hw_cfgmem works.
#
# Image: <this script's folder>/memblaze_vio.bin
#        (SPIx4, uncompressed bitstream ~11 MB, starting at flash address 0x0)
#
# Usage:
#   Option A - batch (no GUI):
#       vivado -mode batch -source program_flash.tcl
#   Option B - Vivado GUI, Hardware Manager -> Tcl Console:
#       source program_flash.tcl
#
# Optional overrides (set BEFORE sourcing; env-var or plain Tcl var):
#   set DESIGN_BIT D:/x/design.bit        ;# override the SPI-bridge bit
#   set BIN        D:/x/another.bin       ;# use a different .bin
#   set FLASH_PART mt25ql256-spi-x1_x2_x4 ;# different cfgmem part
#   set TARGET     */xilinx_tcf/Digilent/2102...A ;# pick the JTAG target
#   set JTAG_FREQ  6000000                ;# lower JTAG clock
#   set ONLY_VERIFY 1                     ;# skip erase/program, verify only
#==============================================================================

# ---- configuration -----------------------------------------------------------
proc getopt {name default} {
    if {[info exists ::env($name)]} { return $::env($name) }
    if {[info exists ::$name]}      { return [set ::$name] }
    return $default
}

# locate the Vivado install root (env var, or walk up from the executable)
proc find_vivado_root {} {
    if {[info exists ::env(XILINX_VIVADO)] && $::env(XILINX_VIVADO) ne ""} {
        return [file normalize $::env(XILINX_VIVADO)]
    }
    set dir [file dirname [file normalize [info nameofexecutable]]]
    while {1} {
        if {[file exists [file join $dir data xicom cfgmem bitfile.zip]]} { return $dir }
        set parent [file dirname $dir]
        if {$parent eq $dir} { return "" }
        set dir $parent
    }
}

set script_dir [file dirname [file normalize [info script]]]
set bin_file    [getopt BIN        [file join $script_dir memblaze_vio.bin]]
set design_bit  [getopt DESIGN_BIT {}]
# -----------------------------------------------------------------------------
# [FLASH PART] 板载 flash 型号 (Micron N25Q256A13EF804F, 3.3 V) 对应的
# Vivado cfgmem 器件名（2024.2 用 MT25Q 命名；千万不要用旧名 n25q256-3.3v-*，
# 2024.2 数据库里不存在 -> 会报 get_cfgmem_parts 为空/下载失败）。
# 换板子/换 flash 时：改这里或运行时 set FLASH_PART <新型号>
# -----------------------------------------------------------------------------
set flash_part  [getopt FLASH_PART {mt25ql256-spi-x1_x2_x4}]
set target      [getopt TARGET     {}]
set jtag_freq   [getopt JTAG_FREQ  {}]
set only_verify [expr {[getopt ONLY_VERIFY 0] eq "1"}]

if {![file exists $bin_file]} { error "Image file not found: $bin_file" }

# ---- connect to the JTAG target (idempotent) ---------------------------------
# If a hw_server / target is ALREADY connected (e.g. the GUI Hardware Manager
# or a standalone hw_server is open, or this session was used before), reuse
# it instead of failing with:
#   ERROR: [Labtoolstcl 44-586] Disconnect server connection, TCP:localhost:3121,
#          before making a new one.
catch {open_hw_manager}
if {[llength [get_hw_servers -quiet]] == 0} {
    connect_hw_server
}
if {[llength [get_hw_targets -quiet]] == 0} {
    if {$target ne ""} {
        open_hw_target $target
    } else {
        open_hw_target
    }
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

# ---- resolve the SPI-bridge bit from the JTAG-scanned part -------------------
if {$design_bit eq ""} {
    set part [get_property PART $hw_dev]
    set vivado_root [find_vivado_root]
    if {$vivado_root eq ""} {
        error "Cannot locate the Vivado install (set XILINX_VIVADO or DESIGN_BIT)"
    }
    set design_bit [file join $vivado_root data xicom cfgmem bitfile "spi_${part}_pullnone.bit"]
    puts "Vivado root: $vivado_root"
    # NOTE: the file may not exist physically - it is streamed from bitfile.zip
    # via a virtual path, so NO existence check / extraction is performed here.
    if {![file exists [file join $vivado_root data xicom cfgmem bitfile.zip]]} {
        error "SPI-bridge bit archive not found: <vivado>/data/xicom/cfgmem/bitfile.zip"
    }
}
puts "SPI-bridge bit (virtual, from bitfile.zip if not overridden): $design_bit"

# (optional) associate probes if the chosen bit has a .ltx next to it
set ltx_file [string map {.bit .ltx} $design_bit]
if {[file exists $ltx_file]} {
    set_property PROBES.FILE $ltx_file $hw_dev
    puts "probes file: $ltx_file"
}

# ---- cfgmem part lookup ------------------------------------------------------
set part_obj [lindex [get_cfgmem_parts $flash_part] 0]
if {$part_obj eq ""} {
    set candidates [lsort -unique [get_cfgmem_parts {*256*}]]
    puts "ERROR: no cfgmem part matches '$flash_part'."
    puts "Try one of these 256 Mb SPI parts:"
    puts [join $candidates "\n"]
    error "cfgmem part '$flash_part' not found"
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

# ---- program the device with the SPI-bridge bit, then program the flash ------
puts "--- program device with the SPI-bridge design ---"
if {[catch {
    create_hw_bitstream -hw_device $hw_dev $design_bit
    program_hw_devices $hw_dev
    refresh_hw_device -update_hw_probes true $hw_dev
} err]} {
    puts "ERROR: could not load the SPI-bridge bit: $err"
    puts "Check that the Vivado install has data/xicom/cfgmem/bitfile.zip"
    puts "with an entry bitfile/spi_<part>_pullnone.bit for part [get_property PART $hw_dev]"
    error $err
}

puts "--- program_hw_cfgmem (erase / blank check / program / verify) ---"
if {[catch {program_hw_cfgmem -hw_cfgmem $cfgmem} err]} {
    puts "----------------------------------------------------------------------"
    puts "ERROR: flash programming failed: $err"
    puts "Expect to see 'design has 1 SPI core(s)' in the log above."
    puts "Troubleshooting (details in FLASH_BURN_GUIDE.md, section 5.1):"
    puts "  1. SPI-bridge bit: auto-resolved from the scanned part; verify"
    puts "     spi_<part>_pullnone.bit exists under data/xicom/cfgmem/bitfile/"
    puts "  2. Lower JTAG clock if unstable: set JTAG_FREQ 6000000"
    puts "  3. Verify part name: mt25ql256-spi-x1_x2_x4 (3.3 V), not mt25qu (1.8 V)"
    puts "----------------------------------------------------------------------"
    error $err
}
puts "=== Flash programming completed (erase / blank check / program / verify) ==="
puts "=== Power-cycle the board (MODE pins = SPI) - it boots from the flash. ==="