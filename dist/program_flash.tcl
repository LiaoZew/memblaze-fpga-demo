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

# the prebuilt bridge bits ship zipped (bitfile.zip); extract the one we need
proc ensure_bridge_bit {design_bit} {
    if {[file exists $design_bit]} { return $design_bit }
    set cfgmem_dir [file normalize [file dirname [file dirname $design_bit]]]
    set zip_file   [file join $cfgmem_dir bitfile.zip]
    if {![file exists $zip_file]} { return "" }
    file mkdir [file dirname $design_bit]
    set entry "bitfile/[file tail $design_bit]"
    set z $zip_file
    set d $design_bit
    set e $entry
    set cmd "Add-Type -AssemblyName System.IO.Compression.FileSystem; \$z=\[System.IO.Compression.ZipFile\]::OpenRead('$z'); \$e=\$z.GetEntry('$e'); \[System.IO.Compression.ZipFileExtensions\]::ExtractToFile(\$e,'$d',\$true); \$z.Dispose()"
    catch {exec powershell -NoProfile -Command $cmd} msg
    if {[file exists $design_bit]} {
        puts "Extracted bridge bit from $zip_file"
        return $design_bit
    }
    puts "Extraction failed: $msg"
    return ""
}

set script_dir [file dirname [file normalize [info script]]]
set bin_file    [getopt BIN        [file join $script_dir memblaze_vio.bin]]
set design_bit  [getopt DESIGN_BIT {}]
set flash_part  [getopt FLASH_PART {mt25ql256-spi-x1_x2_x4}]
set target      [getopt TARGET     {}]
set jtag_freq   [getopt JTAG_FREQ  {}]
set only_verify [expr {[getopt ONLY_VERIFY 0] eq "1"}]

if {![file exists $bin_file]} { error "Image file not found: $bin_file" }

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

# ---- resolve the SPI-bridge bit from the JTAG-scanned part -------------------
if {$design_bit eq ""} {
    set part [get_property PART $hw_dev]
    set vivado_root [find_vivado_root]
    if {$vivado_root eq ""} {
        error "Cannot locate the Vivado install (set XILINX_VIVADO or DESIGN_BIT)"
    }
    set design_bit [file join $vivado_root data xicom cfgmem bitfile "spi_${part}_pullnone.bit"]
    puts "Vivado root: $vivado_root"
}
if {![file exists $design_bit]} {
    set design_bit [ensure_bridge_bit $design_bit]
}
if {![file exists $design_bit]} {
    puts "ERROR: SPI-bridge bit not found: $design_bit"
    puts "It should come from <vivado>/data/xicom/cfgmem/bitfile.zip "
    puts "(entry bitfile/spi_<part>_pullnone.bit)."
    error "SPI-bridge bitstream not found"
}
puts "SPI-bridge bit: $design_bit"

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
create_hw_bitstream -hw_device $hw_dev $design_bit
program_hw_devices $hw_dev
refresh_hw_device -update_hw_probes true $hw_dev

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