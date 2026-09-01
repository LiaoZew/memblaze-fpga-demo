#==============================================================================
# MemBlaze xc7k325tffg900-2 - ddr_vio : PL 用 VIO 控制 DDR3 读写
#
#   MIG 7 Series (DDR3, 72-bit)   +   VIO 控制/观察   +   PL app 状态机
#   VIO probe_out : rst / wr_en / rd_en / wr_addr / rd_addr / wr_data[71:0]
#   VIO probe_in  : init_calib_done / app_rdy / app_wdf_rdy / rd_valid /
#                   rd_data[71:0] / busy / done
#   时钟: D27 50MHz(单端) -> MIG sys_clk_i；ui_clk = MIG 内部时钟(例 400MHz)
#   引脚: board_reference/ddr3_72bit_converted.xdc (SSTL15, banks 32/33/34)
#
# Run:
#   vivado -mode batch -source scripts/create_project.tcl
# Publishes dist/ddr_vio.bit/.bin
#==============================================================================

set part          xc7k325tffg900-2
set proj_name     ddr_vio
set top_module    ddr_vio_top
set script_dir    [file dirname [info script]]
set root          [file normalize [file join $script_dir ..]]
set repo_root     [file normalize [file join $script_dir ../..]]
set src_dir       [file join $root src]
set proj_dir      [file join $root projects]

puts "=== MemBlaze ddr_vio project: $proj_name (part $part) ==="

if {[file exists $proj_dir]} { file delete -force $proj_dir }
create_project -force -dir $proj_dir -part $part $proj_name
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

#------------------------------------------------------------------------------
# MIG 7 Series IP: generated once via the GUI wizard (MIG cannot be fully
# configured through Tcl - its parameters are locked after create_ip).
# Once ddr_vio/ip/mig_0/mig_0.xci exists this script picks it up and builds.
#   GUI steps (do this once):
#     1) IP Catalog -> Memory & Storage -> MIG 7 Series  (right-click -> Customize IP)
#     2) Name: mig_0,  Save under ddr_vio/ip
#        Memory Type: DDR3 | Memory Part: MT41K512M8DA-125
#        Speed Bin / MT/s: 800 (400 MHz clock)  (any supported speed is fine)
#        Memory Width: 72 | ECC: Disabled
#        Input Clock Period: 20000 ps (50 MHz clock, D27)
#        Input Clock Type: Single-Ended
#        Internal Vref / System Reset: defaults
#        Pin Selection: click "Import Pin Files" and load ddr_vio/pins_bank.csv
#          (then "Validate" - 72-bit -> DQS groups 0..8 must map cleanly)
#        OR skip pin import; the board pins are enforced later anyway by
#        board_reference/ddr3_72bit_converted.xdc (identical signal names).
#     3) OK -> the generated mig_0.xci appears under ddr_vio/ip/mig_0/
#------------------------------------------------------------------------------
set mig_xci [file join $root ip mig_0 mig_0.xci]
set mig_defs [get_ipdefs -all -filter {NAME == mig_7series}]
if {[llength $mig_defs] == 0} { error "mig_7series IP not found in the catalog" }
set mig_ver [lindex [split [get_property VLNV [lindex $mig_defs end]] :] 3]
puts "Using MIG version: $mig_ver"
if {![file exists $mig_xci]} {
    puts ""
    puts "=============================================================="
    puts " MIG IP NOT FOUND: ddr_vio/ip/mig_0/mig_0.xci"
    puts " MIG 7 Series cannot be configured from Tcl (parameters are"
    puts " locked); create it once through the GUI wizard:"
    puts ""
    puts "   1) open the project in the GUI (scripts/open_gui.tcl)"
    puts "   2) IP Catalog -> Memory & Storage -> MIG 7 Series"
    puts "      right-click -> Customize IP"
    puts "      Name 'mig_0', save to ddr_vio/ip"
    puts "      Memory: DDR3, part MT41K512M8DA-125, 72-bit, no ECC"
    puts "      Speed 800 Mt/s;  Input clock 20000 ps, Single-Ended"
    puts "      Pins:  Import ddr_vio/pins_bank.csv  (then Validate)"
    puts "      (the board pins are anyway enforced by"
    puts "       board_reference/ddr3_72bit_converted.xdc)"
    puts "   3) re-run this script"
    puts "=============================================================="
    exit 0
}
add_files -norecurse $mig_xci
puts "MIG IP loaded: $mig_xci"

#------------------------------------------------------------------------------
# VIO: 6 output probes (control) + 8 input probes (observe)
#------------------------------------------------------------------------------
create_ip -name vio -vendor xilinx.com -library ip -version [lindex [split [get_property VLNV [lindex [get_ipdefs -all -filter {NAME == vio}] end]] :] 3] -module_name vio_0
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN  {8} \
    CONFIG.C_NUM_PROBE_OUT {7} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} \
    CONFIG.C_PROBE_OUT1_WIDTH {1} \
    CONFIG.C_PROBE_OUT2_WIDTH {1} \
    CONFIG.C_PROBE_OUT3_WIDTH {27} \
    CONFIG.C_PROBE_OUT4_WIDTH {27} \
    CONFIG.C_PROBE_OUT5_WIDTH {72} \
    CONFIG.C_PROBE_OUT6_WIDTH {1} \
    CONFIG.C_PROBE_IN0_WIDTH {1} \
    CONFIG.C_PROBE_IN1_WIDTH {1} \
    CONFIG.C_PROBE_IN2_WIDTH {1} \
    CONFIG.C_PROBE_IN3_WIDTH {1} \
    CONFIG.C_PROBE_IN4_WIDTH {72} \
    CONFIG.C_PROBE_IN5_WIDTH {1} \
    CONFIG.C_PROBE_IN6_WIDTH {1} \
    CONFIG.C_PROBE_IN7_WIDTH {1} \
] [get_ips vio_0]

#------------------------------------------------------------------------------
# Sources + constraints
#------------------------------------------------------------------------------
foreach f {top.v ddr_ctrl.v} {
    add_files -norecurse -fileset sources_1 [file join $src_dir $f]
}
add_files -norecurse -fileset constrs_1 [file join $src_dir ${proj_name}.xdc]
add_files -norecurse -fileset constrs_1 [file join $repo_root board_reference ddr3_72bit_converted.xdc]
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

#------------------------------------------------------------------------------
# Run flow
#------------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH STATUS: $synth_status"
if {[string first "Complete" $synth_status] < 0} { error "Synthesis failed: $synth_status" }

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL STATUS: $impl_status"
if {[string first "Complete" $impl_status] < 0} { error "Implementation failed: $impl_status" }

#------------------------------------------------------------------------------
# Publish
#------------------------------------------------------------------------------
set dist_dir [file join $repo_root dist]
file mkdir $dist_dir
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_src [lindex [glob -nocomplain [file join $impl_dir *.bit]] 0]
set ltx_src [lindex [glob -nocomplain [file join $impl_dir *.ltx]] 0]
set dcp_src [lindex [glob -nocomplain [file join $impl_dir *_routed.dcp]] 0]

file copy -force $bit_src [file join $dist_dir "$proj_name.bit"]
puts "PUBLISH: [file join $dist_dir "$proj_name.bit"]"
if {$ltx_src ne ""} {
    file copy -force $ltx_src [file join $dist_dir "$proj_name.ltx"]
    puts "PUBLISH: [file join $dist_dir "$proj_name.ltx"]"
}
if {$dcp_src ne "" && $bit_src ne ""} {
    open_checkpoint $dcp_src
    write_cfgmem -force -format bin -interface SPIx4 \
                 -loadbit "up 0x0 $bit_src" \
                 -file [file join $impl_dir "$proj_name.bin"]
    file copy -force [file join $impl_dir "$proj_name.bin"] [file join $dist_dir "$proj_name.bin"]
    puts "PUBLISH: [file join $dist_dir "$proj_name.bin"]"
    close_design
}
puts "=== DONE. dist/$proj_name.bit/.bin ==="