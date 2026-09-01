#==============================================================================
# Merge the MicroBlaze ELF into the bitstream and regenerate the SPIx4 flash
# image, so the soft-core program runs standalone after power-up.
#
# Run AFTER scripts/create_project.tcl AND scripts/build_elf.tcl
# (needs dist/sgen_uart.elf):
#   vivado -mode batch -source sgen_uart/scripts/merge_elf.tcl
#
# Publishes (overwrites):
#   dist/sgen_uart.bit  - bitstream with the program embedded (JTAG program
#                      and the LEDs run immediately - no separate download)
#   dist/sgen_uart.bin  - SPIx4 flash image with the program embedded
#==============================================================================

set script_dir [file dirname [info script]]
set root       [file normalize [file join $script_dir ..]]
set repo_root  [file normalize [file join $script_dir ../..]]
set impl_dir   [file join $root projects sgen_uart.runs impl_1]
set dist_dir   [file join $repo_root dist]

set bit_src [lindex [glob -nocomplain [file join $impl_dir *.bit]] 0]
set mmi_src [lindex [glob -nocomplain [file join $impl_dir *.mmi]] 0]
set elf_src [file join $dist_dir sgen_uart.elf]

if {$bit_src eq "" || $mmi_src eq "" || ![file exists $elf_src]} {
    error "missing inputs: bit=$bit_src mmi=$mmi_src elf=$elf_src"
}

# updatemem ships as a standalone tool next to Vivado (not a Tcl command)
set exe_path [file normalize [info nameofexecutable]]
set viv_bin [file dirname [file dirname [file dirname $exe_path]]]
set um_exe [file join $viv_bin unwrapped win64.o updatemem.exe]
set um_bat [file join $viv_bin updatemem.bat]
if {[file exists $um_exe]} { set um $um_exe } else { set um $um_bat }
puts "viv_bin=$viv_bin updatemem=$um"
if {![file exists $um]} { error "updatemem not found near $viv_bin" }

set merged_bit [file join $impl_dir sgen_uart_merged.bit]
puts "updatemem: bit=$bit_src mmi=$mmi_src elf=$elf_src"
set merged_ok 0
foreach mproc {u_sys/system_i/microblaze_0 system_i/microblaze_0} {
    set cmd "$um -meminfo $mmi_src -bit $bit_src -data $elf_src -proc $mproc -force -out $merged_bit"
    puts "RUN: $cmd"
    catch {exec {*}[split $cmd]} um_result
    if {[file exists $merged_bit]} {
        puts "updatemem proc=$mproc OK"
        set merged_ok 1
        break
    }
    file delete -force $merged_bit
}
if {!$merged_ok} {
    puts "updatemem output: $um_result"
    error "updatemem failed - no merged bitstream produced"
}
puts "MERGED: $merged_bit"

file copy -force $merged_bit [file join $dist_dir sgen_uart.bit]
puts "PUBLISH: [file join $dist_dir sgen_uart.bit]  (ELF embedded)"

# regenerate the flash image from the merged bitstream
set dcp_src [lindex [glob -nocomplain [file join $impl_dir *_routed.dcp]] 0]
if {$dcp_src ne ""} {
    open_checkpoint $dcp_src
    write_cfgmem -force -format bin -interface SPIx4 \
                 -loadbit "up 0x0 $merged_bit" \
                 -file [file join $impl_dir sgen_uart.bin]
    file copy -force [file join $impl_dir sgen_uart.bin] [file join $dist_dir sgen_uart.bin]
    puts "PUBLISH: [file join $dist_dir sgen_uart.bin]  (ELF embedded)"
    close_design
} else {
    puts "WARNING: no routed checkpoint, .bin not regenerated"
}
puts "=== DONE. dist/sgen_uart.bit/.bin now include the MicroBlaze program. ==="
puts "=== Burn: vivado -mode batch -source dist/program_flash.tcl -tclargs sgen_uart.bin ==="