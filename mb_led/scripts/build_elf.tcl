#==============================================================================
# Build the MicroBlaze application (ELF) with Vitis/xsct and publish it to
# dist/mb_led.elf
#
# Run AFTER scripts/create_project.tcl (which exports mb_led.xsa):
#   D:\xilinx\rundir3\Vitis\2024.2\bin\xsct.bat scripts/build_elf.tcl
#==============================================================================

set script_dir [file dirname [info script]]
set root       [file normalize [file join $script_dir ..]]
set repo_root  [file normalize [file join $script_dir ../..]]
set xsa_file   [file join $root mb_led.xsa]
set ws_dir     [file join $root app_ws]

if {![file exists $xsa_file]} {
    error "mb_led.xsa not found - run scripts/create_project.tcl first"
}

file mkdir $ws_dir
setws $ws_dir

# platform + standalone domain
platform create -name mb_led_platform -hw $xsa_file
domain create -name standalone_domain -proc microblaze_0 -os standalone

# empty app, then drop in our main.c
app create -name led_app -platform mb_led_platform -domain standalone_domain \
           -template "Empty Application"
file copy -force [file join $root src main.c] [file join $ws_dir led_app src main.c]

app build -name led_app

# publish the ELF next to the other artifacts
set elf_src [file join $ws_dir led_app Debug led_app.elf]
set dist    [file join $repo_root dist]
file mkdir $dist
file copy -force $elf_src [file join $dist mb_led.elf]
puts "=== ELF published: [file join $dist mb_led.elf] ==="

puts "=== Download & run (via xsdb/Hardware Manager): ==="
puts "    connect; target; rst -processor; dow dist/mb_led.elf; con"