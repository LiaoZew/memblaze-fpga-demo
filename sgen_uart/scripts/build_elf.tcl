#==============================================================================
# Build the MicroBlaze application (ELF) with Vitis/xsct and publish it to
# dist/sgen_uart.elf
#
# Run AFTER scripts/create_project.tcl (which exports sgen_uart.xsa):
#   D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat scripts/build_elf.tcl
#==============================================================================

set script_dir [file dirname [info script]]
set root       [file normalize [file join $script_dir ..]]
set repo_root  [file normalize [file join $script_dir ../..]]
set xsa_file   [file join $root sgen_uart.xsa]
set ws_dir     [file join $root app_ws]

if {![file exists $xsa_file]} {
    error "sgen_uart.xsa not found - run scripts/create_project.tcl first"
}

file mkdir $ws_dir
setws $ws_dir

# platform + standalone domain
platform create -name sgen_uart_platform -hw $xsa_file
domain create -name standalone_domain -proc microblaze_0 -os standalone

# empty app, then drop in our main.c
app create -name led_app -platform sgen_uart_platform -domain standalone_domain \
           -template "Empty Application"
file copy -force [file join $root src main.c] [file join $ws_dir led_app src main.c]

# first app build generates the Debug makefile tree (and usually the ELF);
# if the ELF is still missing, force the link with 'make all' (xsct's
# 'app build' may only rebuild the BSP on subsequent runs)
app build -name led_app
set app_elf [file join $ws_dir led_app Debug led_app.elf]
if {![file exists $app_elf]} {
    set app_debug_dir [file join $ws_dir led_app Debug]
    cd $app_debug_dir
    if {[catch {exec make all 2>@1} make_out]} {
        puts "app build output: $make_out"
        error "application build failed"
    }
    puts "app build (make all): OK"
}
if {![file exists $app_elf]} { error "no ELF produced" }

# publish the ELF next to the other artifacts
set elf_src [file join $ws_dir led_app Debug led_app.elf]
set dist    [file join $repo_root dist]
file mkdir $dist
file copy -force $elf_src [file join $dist sgen_uart.elf]
puts "=== ELF published: [file join $dist sgen_uart.elf] ==="

puts "=== Download & run (via xsdb/Hardware Manager): ==="
puts "    connect; target; rst -processor; dow dist/sgen_uart.elf; con"