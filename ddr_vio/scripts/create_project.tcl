#==============================================================================
# MemBlaze xc7k325tffg900-2 - ddr_vio : PL 用 VIO 控制 DDR3 读写
#
#   MIG 7 Series (DDR3, 72-bit)   +   VIO 控制/观察   +   PL app 状态机
#   VIO probe_out : rst / wr_en / rd_en / wr_addr / rd_addr / wr_data[71:0]
#   VIO probe_in  : init_calib_done / app_rdy / app_wdf_rdy / rd_valid /
#                   rd_data[71:0] / busy / done
#   时钟: D27 50MHz(单端) -> MIG sys_clk_i；ui_clk = MIG 内部时钟(例 400MHz)
#   引脚: board_reference/ddr3_64bit_converted.xdc (SSTL15, banks 32/33/34)
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
#        board_reference/ddr3_64bit_converted.xdc (identical signal names).
#     3) OK -> the generated mig_0.xci appears under ddr_vio/ip/mig_0/
#------------------------------------------------------------------------------
set mig_dir  [file join $root ip mig_0]
set mig_prj  [file join $mig_dir mig.prj]
set mig_defs [get_ipdefs -all -filter {NAME == mig_7series}]
if {[llength $mig_defs] == 0} { error "mig_7series IP not found in the catalog" }
set mig_ver [lindex [split [get_property VLNV [lindex $mig_defs end]] :] 3]
puts "Using MIG version: $mig_ver"

# regenerate the MIG IP from the .prj every run (stale dirs cause
# "Unconfigured MIG instance" errors)
foreach d [glob -nocomplain [file join $mig_dir *]] {
    if {[string match *mig_0_* [file tail $d]]} { file delete -force $d }
}
file delete -force [file join $mig_dir mig_0.xci]

if {![file exists $mig_prj]} {
    puts ""
    puts "=============================================================="
    puts " MIG project file NOT FOUND: ddr_vio/ip/mig_0/mig.prj"
    puts " (a prj-driven MIG is fully scriptable; the GUI path is a"
    puts "  fallback: IP Catalog -> MIG 7 Series -> Customize IP,"
    puts "  save mig_0 under ddr_vio/ip)"
    puts "=============================================================="
    exit 0
}

puts "Generating MIG IP from $mig_prj ..."
create_ip -name mig_7series -vendor xilinx.com -library ip -version $mig_ver \
          -module_name mig_0
set_property CONFIG.XML_INPUT_FILE $mig_prj [get_ips mig_0]
generate_target all [get_ips mig_0]

set mig_xci [file join $proj_dir ${proj_name}.srcs sources_1 ip mig_0 mig_0.xci]
if {![file exists $mig_xci]} {
    set mig_xci [lindex [lsort [glob -nocomplain [file join $mig_dir * mig_0.xci]]] end]
}
if {$mig_xci eq ""} { error "MIG xci not produced from $mig_prj" }
add_files -norecurse $mig_xci
generate_target all [get_files -quiet mig_0.xci]

# MIG 4.2 prj-driven outputs miss the dlib controller RTL, and the OOC run
# then fails with "module memc_ui_top_std not found". Workaround:
#  - put MIG on global synthesis (no OOC run), and
#  - add the dlib controller sources directly to the top-level fileset.
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $mig_xci]
set dlib_d3 {D:/xilinx/rundir3/Vivado/2024.2/data/ip/xilinx/mig_7series_v4_2/data/dlib/7series/ddr3_sdram/verilog/rtl}
set dlib_cm {D:/xilinx/rundir3/Vivado/2024.2/data/ip/xilinx/mig_7series_v4_2/data/dlib/common}
set user_rtl [file join $mig_dir dlib_ext]
set dlib_files [list]
foreach dir [list $dlib_d3 $dlib_cm] {
    set dlib_files [concat $dlib_files \
        [glob -nocomplain [file join $dir * *.v]] \
        [glob -nocomplain [file join $dir * * *.v]] \
        [glob -nocomplain [file join $dir * * * *.v]] \
        [glob -nocomplain [file join $dir * * * * *.v]]]
}
set dlib_files [lsort -unique $dlib_files]
puts "DLIB_RTL_COUNT=[llength $dlib_files]"
# copy dlib sources INTO the generated user_design/rtl tree (that is what the
# synthesizer reads for the MIG IP in global mode)
# only the one missing controller RTL: memc_ui_top_std.v
set extra_dlib [list]
foreach f [glob -nocomplain [file join $dlib_d3 ip_top mig_7series_v4_2_memc_ui_top_std.v]] { lappend extra_dlib $f }
file delete -force $user_rtl
file mkdir $user_rtl
set dlib_added 0
foreach f $extra_dlib {
    file copy -force $f $user_rtl
    incr dlib_added
}
puts "DLIB_ADDED=$dlib_added"
puts "MIG IP loaded (global synth + dlib rtl): $mig_xci"

# drop the OOC run so the global synthesizer compiles the MIG RTL directly
catch {reset_run -quiet mig_0_synth_1}
catch {delete_runs -force -quiet mig_0_synth_1}


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
add_files -norecurse -fileset constrs_1 [file join $repo_root board_reference ddr3_64bit_converted.xdc]
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

#------------------------------------------------------------------------------
# Run flow
#------------------------------------------------------------------------------
puts "DBG_MEMC_IN_SOURCES=[llength [get_files -quiet -filter {NAME =~ *memc_ui_top_std*} -of_objects [get_filesets sources_1]]]"
puts "DBG_VERILOG_TOTAL=[llength [get_files -quiet -filter {FILE_TYPE == Verilog} -of_objects [get_filesets sources_1]]]"
update_compile_order -fileset sources_1
# force the synthesizer process to (re)read the sources incl. the dlib extras:
# a PRE hook inside synth_1 re-adds the dlib dir and updates compile order
set dlib_ext_dir [file join $mig_dir dlib_ext]
set hookf [file join $mig_dir pre_synth.tcl]
set fh [open $hookf w]
puts $fh "add_files -norecurse -fileset sources_1 [glob -nocomplain [file join $dlib_ext_dir *.v]]"
puts $fh "update_compile_order -fileset sources_1"
close $fh
set_property STEPS.SYNTH_DESIGN.TCL.PRE $hookf [get_runs synth_1]
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