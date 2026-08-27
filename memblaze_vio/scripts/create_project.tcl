#==============================================================================
# MemBlaze xc7k325tffg900-2 - project build script (Vivado 2024.2)
#
# Run:
#   vivado -mode batch -source scripts/create_project.tcl
#
# Creating a NEW project for this board:
#   1. create a new folder (e.g. <new_proj>/) and copy this scripts/ folder
#   2. set proj_name below to the new project name
#      (artifacts published to <root>/dist are named <proj_name>.bit/.ltx)
#   3. put the top module + constraint files in src/ (update add_files below)
#   4. run this script (it synthesizes, implements and writes the bitstream)
#   5. run scripts/gen_flash_bin.tcl to produce the SPIx4 flash image
#
# Artifact naming convention (many projects on the same board):
#   dist/<proj_name>.bit  - JTAG bitstream
#   dist/<proj_name>.ltx  - VIO debug probes (must match the .bit)
#   dist/<proj_name>.bin  - SPIx4 flash image  (from gen_flash_bin.tcl)
#==============================================================================

set part          xc7k325tffg900-2
set proj_name     memblaze_vio
set script_dir    [file dirname [info script]]
set root          [file normalize [file join $script_dir ..]]
set repo_root     [file normalize [file join $script_dir ../..]]
set src_dir       [file join $root src]
set proj_dir      [file join $root projects]

puts "=== MemBlaze project: $proj_name (part $part) ==="

# Fresh project
if {[file exists $proj_dir]} {
    file delete -force $proj_dir
}
create_project -force -dir $proj_dir -part $part $proj_name
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

#------------------------------------------------------------------------------
# VIO core: 3 x 1-bit output probes, no input probes
#------------------------------------------------------------------------------
set vio_defs [get_ipdefs -all -filter {NAME == vio}]
if {[llength $vio_defs] == 0} {
    error "VIO IP definition not found in catalog"
}
set vio_ver [lindex [split [get_property VLNV [lindex $vio_defs end]] :] 3]
puts "Using VIO IP version: $vio_ver"
create_ip -name vio -vendor xilinx.com -library ip -version $vio_ver -module_name vio_0
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN      {0} \
    CONFIG.C_NUM_PROBE_OUT     {3} \
    CONFIG.C_PROBE_OUT0_WIDTH  {1} \
    CONFIG.C_PROBE_OUT1_WIDTH  {1} \
    CONFIG.C_PROBE_OUT2_WIDTH  {1} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0} \
    CONFIG.C_PROBE_OUT1_INIT_VAL {0} \
    CONFIG.C_PROBE_OUT2_INIT_VAL {0} \
] [get_ips vio_0]
generate_target all [get_ips vio_0]

#------------------------------------------------------------------------------
# Design sources + constraints
#------------------------------------------------------------------------------
add_files -norecurse -fileset sources_1 [file join $src_dir top.v]
add_files -norecurse -fileset constrs_1 [file join $src_dir memblaze_led.xdc]
set_property top memblaze_vio_top [current_fileset]
update_compile_order -fileset sources_1

#------------------------------------------------------------------------------
# Run synthesis -> implementation -> bitstream
#------------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH STATUS: $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    error "Synthesis failed: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL STATUS: $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    error "Implementation failed: $impl_status"
}

#------------------------------------------------------------------------------
# Publish project-named artifacts to <repo_root>/dist/
#------------------------------------------------------------------------------
set dist_dir [file join $repo_root dist]
file mkdir $dist_dir
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_src  [lindex [glob -nocomplain [file join $impl_dir *.bit]] 0]
set ltx_src  [lindex [glob -nocomplain [file join $impl_dir *.ltx]] 0]
if {$bit_src ne ""} {
    file copy -force $bit_src [file join $dist_dir "$proj_name.bit"]
    puts "PUBLISH: [file join $dist_dir "$proj_name.bit"]"
} else {
    puts "WARNING: no .bit found in $impl_dir"
}
if {$ltx_src ne ""} {
    file copy -force $ltx_src [file join $dist_dir "$proj_name.ltx"]
    puts "PUBLISH: [file join $dist_dir "$proj_name.ltx"]"
} else {
    puts "WARNING: no .ltx found (design has no debug cores)"
}

puts "=== DONE. Bitstream: $bit_src"
puts "=== Flash image: run scripts/gen_flash_bin.tcl"
puts "=== Hardware: program dist/$proj_name.bit (+ .ltx for hw_vio),
       or burn dist/$proj_name.bin into the SPI flash (see dist/FLASH_BURN_GUIDE.md)."