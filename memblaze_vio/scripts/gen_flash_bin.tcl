# Generate SPI flash image (.bin, SPIx4) and a copy for distribution
set impl_dir  [file normalize [file join [file dirname [info script]] .. projects memblaze_vio.runs impl_1]]
set bit_file  [file join $impl_dir memblaze_vio_top.bit]
set bin_file  [file join $impl_dir memblaze_vio_top.bin]

if {![file exists $bit_file]} {
    error "bitstream not found: $bit_file (run create_project.tcl first)"
}

open_checkpoint [file join $impl_dir memblaze_vio_top_routed.dcp]
write_cfgmem -force -format bin -interface SPIx4 \
             -loadbit "up 0x0 $bit_file" \
             -file $bin_file
puts "=== SPIx4 flash image: $bin_file"
close_design