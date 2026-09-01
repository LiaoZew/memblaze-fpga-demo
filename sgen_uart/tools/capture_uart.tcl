#==============================================================================
# Capture the MicroBlaze JTAG UART output and save it as CSV, then visualize.
#
#   xsct.bat sgen_uart\tools\capture_uart.tcl [R|S] [-program]
#     R / S : wave selector for the mwr trigger (default R)
#     -program: load dist/sgen_uart.bit (ELF embedded) WHILE the UART read
#               window is already open - the boot banner and the auto sine
#               upload are captured (leaving the window closed during boot
#               could otherwise let the MDM TX FIFO fill and stall printf)
#   python sgen_uart/tools/plot_csv.py sgen_uart/tools/out/capture.csv
#==============================================================================
set cap_ms 12000
set args_l [lrange $argv 0 end]
set sel "R"
set do_program 0
foreach a $args_l {
    if {$a eq "-program"} { set do_program 1 } else { set sel $a }
}
set out_file [file join [file dirname [info script]] out capture.csv]
file mkdir [file dirname $out_file]

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

# ---- OPEN the UART read window first (drains the MDM TX FIFO) ----
set fp [open $out_file w]
if {[catch {readjtaguart -start -handle $fp} e]} {
    puts "readjtaguart: $e"
    puts "This xsct environment did not expose a JTAG-UART target. Workaround:"
    puts "  1) Vitis IDE -> Serial Terminal (JTAG UART), trigger '$sel',"
    puts "     save the printed CSV lines to $out_file"
    puts "  2) plot: python sgen_uart/tools/plot_csv.py $out_file"
    close $fp
    exit 1
}

# ---- optional: program the merged bit while the window is open ----
if {$do_program} {
    if {[catch {targets -set -filter {name =~ "*xc7k325t*"}}]} {
        puts "NOTE: no FPGA target found to program"
    }
    catch {fpga -file [file join [file dirname [info script]] .. .. dist sgen_uart.bit]} fp
    puts "fpga program: $fp"
    after 1500
    # re-select the MicroBlaze target (it re-enumerates after programming)
    set picked 0
    catch {targets -set -filter {name =~ "*MicroBlaze #0*"} ; set picked 1}
    catch {targets -set -filter {name =~ "*MicroBlaze*"}     ; set picked 1}
}

# ---- diagnostics (UART is being drained concurrently) ----
if {$picked} {
    set d ""
    catch {mrd -size w 0xC0000000 4} d
    puts "ACQ_BRAM[0..3] = $d  (sine starts 0,3212,6393,9512)"
    catch {rrd pc} pc1
    puts "PC = $pc1  (nonzero/advancing proves the soft-core is executing)"
}

# ---- kick the firmware (MDM uart RX FIFO register @ 0x41400004) ----
set mr ""
catch {mwr -force 0x41400004 [format %d $ascii]} mr
if {$mr ne ""} {
    puts "NOTE: mwr failed ($mr) - reading the auto upload / banner only."
}

after $cap_ms
readjtaguart -stop
close $fp

set n [llength [read [open $out_file r]]]
puts "captured $n line(s) -> $out_file"
if {$n == 0} {
    puts "No UART data received. Check:"
    puts "  - is the design running? (re-run with -program)"
    puts "  - does this xsct expose a JTAG-UART target? If not, use the"
    puts "    Vitis IDE Serial Terminal and save its output as CSV."
} else {
    puts "plot: python sgen_uart/tools/plot_csv.py $out_file"
}