#==============================================================================
# MemBlaze xc7k325tffg900-2 - VIO LED demo - project build script (Vivado 2024.2)
#
# Run:
#   vivado -mode batch -source scripts/create_project.tcl
#
# Creates project "memblaze_vio", adds a VIO core with 3 x 1-bit output
# probes (drive LED_G / LED_Y / LED_R), synthesizes, implements and writes
# the bitstream.
#==============================================================================

set part          xc7k325tffg900-2
set proj_name     memblaze_vio
set script_dir    [file dirname [info script]]
set root          [file normalize [file join $script_dir ..]]
set src_dir       [file join $root src]
set proj_dir      [file join $root projects]

puts "=== MemBlaze VIO LED project: $proj_name (part $part) ==="

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

set bit_file [file join [get_property DIRECTORY [get_runs impl_1]] memblaze_vio_top.bit]
puts "=== DONE: bitstream at $bit_file"
puts "=== Open Hardware Manager, program the device, then use the hw_vio "
puts "=== 'vio_0' window to toggle probe_out0/1/2 (LED_G/LED_Y/LED_R)."