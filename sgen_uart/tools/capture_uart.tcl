#==============================================================================
# Capture one upload from the MicroBlaze JTAG UART and save it as CSV,
# then visualize with Python.
#
#   D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat tools\capture_uart.tcl R
#   (optional arg: wave selector R(amp) or S(ine), default R)
#   python tools/plot_csv.py tools/out/capture.csv
#
# How: connect -> write the command character into the MDM UART RX FIFO
# (mwr to 0x41400004, the MDM uart RX register) -> the firmware runs one
# cycle and streams index,value lines -> readjtaguart captures them.
#==============================================================================
set cap_ms 4000
set sel [expr {[llength $argv] > 0 ? [lindex $argv 0] : "R"}]
set out_file [file join [file dirname [info script]] out capture.csv]
file mkdir [file dirname $out_file]

# ASCII code of the command character
scan $sel %c ascii

connect
# give the target a moment
after 500

# kick the firmware over the JTAG UART (MDM uart RX FIFO reg @ 0x41400004)
catch {mwr -force 0x41400004 [format %d $ascii]}

# capture the UART stream
set fp [open $out_file w]
readjtaguart -start -handle $fp
after $cap_ms
readjtaguart -stop
close $fp

puts "captured -> $out_file (run: python sgen_uart/tools/plot_csv.py $out_file)"