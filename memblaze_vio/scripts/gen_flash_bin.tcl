#==============================================================================
# Generate the SPIx4 flash image (.bin) from the implemented design and
# publish it to dist/<proj_name>.bin
#
# Run after scripts/create_project.tcl has completed:
#   vivado -mode batch -source scripts/gen_flash_bin.tcl
#
# The board configures from an SPI flash in SPIx4 mode (see ddr.xdc:
# CONFIG_MODE SPIx4, SPI_BUSWIDTH 4, CONFIGRATE 66). The .bin image starts
# at flash address 0x0 and is 16 MB (based on the uncompressed bitstream).
#==============================================================================

set part          xc7k325tffg900-2
set proj_name     memblaze_vio
set script_dir    [file dirname [info script]]
set proj_root     [file normalize [file join $script_dir ..]]
set repo_root     [file normalize [file join $script_dir ../..]]
set impl_dir      [file join $proj_root projects memblaze_vio.runs impl_1]
set dist_dir      [file join $repo_root dist]

set bit_src [lindex [glob -nocomplain [file join $impl_dir *.bit]] 0]
if {$bit_src eq ""} {
    error "no .bit found in $impl_dir - run scripts/create_project.tcl first"
}
set dcp_src [lindex [glob -nocomplain [file join $impl_dir *_routed.dcp]] 0]
if {$dcp_src eq ""} {
    error "no *_routed.dcp found in $impl_dir - run scripts/create_project.tcl first"
}

file mkdir $dist_dir
open_checkpoint $dcp_src
write_cfgmem -force -format bin -interface SPIx4 \
             -loadbit "up 0x0 $bit_src" \
             -file [file join $impl_dir "$proj_name.bin"]
file copy -force [file join $impl_dir "$proj_name.bin"] [file join $dist_dir "$proj_name.bin"]
puts "=== Published flash image: [file join $dist_dir "$proj_name.bin"]"
close_design