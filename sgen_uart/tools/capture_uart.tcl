#==============================================================================
# Capture one upload from the MicroBlaze JTAG UART and save it as CSV,
# then visualize with Python.
#
#   D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat sgen_uart\tools\capture_uart.tcl R
#   (optional arg: wave selector R(amp) or S(ine), default R)
#   python sgen_uart/tools/plot_csv.py sgen_uart/tools/out/capture.csv
#
# How: connect -> select a target -> write the command character into the
# MDM UART RX FIFO (mwr to 0x41400004) -> the firmware runs one cycle and
# streams index,value lines -> readjtaguart captures them.
#
# Note: mwr/readjtaguart need a *current target*. If the tool does not
# expose a JTAG-UART capable target (some setups only show the FPGA), the
# script prints a hint - in that case use the Vitis IDE Serial Terminal.
#==============================================================================
set cap_ms 4000
set sel [expr {[llength $argv] > 0 ? [lindex $argv 0] : "R"}]
set out_file [file join [file dirname [info script]] out capture.csv]
file mkdir [file dirname $out_file]

# ASCII code of the command character
scan $sel %c ascii

connect
after 500

# ---- select a target (required by mwr and readjtaguart) ----
set picked 0
catch {targets -set -filter {name =~ "*MicroBlaze #0*"} ; set picked 1}
catch {targets -set -filter {name =~ "*MicroBlaze*"}     ; set picked 1}
catch {targets -set -filter {name =~ "*JTAG UART*"}      ; set picked 1}
catch {targets -set -filter {name =~ "*Uart*"}           ; set picked 1}
if {!$picked} {
    puts "NOTE: no MicroBlaze/JTAG-UART target selected - please run 'targets'"
    puts "      and pick the MicroBlaze (or JTAG UART) target manually."
}

# ---- kick the firmware (MDM uart RX FIFO register @ 0x41400004) ----
set mr ""
catch {mwr -force 0x41400004 [format %d $ascii]} mr
if {$mr ne ""} {
    puts "NOTE: mwr failed ($mr) - start the upload from the console instead"
    puts "      (xsct: jtagterminal -> type $sel), then rerun the capture part."
}

# ---- capture the UART stream ----
set fp [open $out_file w]
if {[catch {readjtaguart -start -handle $fp} e]} {
    puts "readjtaguart: $e"
    puts "This xsct environment did not expose a JTAG-UART target (the"
    puts "MicroBlaze UART may be seen as a plain target). Workaround:"
    puts "  1) Vitis IDE -> Serial Terminal -> JTAG UART, trigger '$sel',"
    puts "     save the printed CSV lines to $out_file"
    puts "  2) then plot: python sgen_uart/tools/plot_csv.py $out_file"
    close $fp
    exit 1
}
after $cap_ms
readjtaguart -stop
close $fp

puts "captured -> $out_file (run: python sgen_uart/tools/plot_csv.py $out_file)"