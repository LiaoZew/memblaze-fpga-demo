#==============================================================================
# MemBlaze xc7k325tffg900-2 - MicroBlaze LED project - ONE-CLICK build script
#
# Run:
#   vivado -mode batch -source scripts/create_project.tcl
#
# Builds a minimal MicroBlaze soft-core design:
#   MicroBlaze (no caches, debug enabled)
#     + AXI GPIO (3-bit output) -> LEDs  (AXI-Lite interface controlling LEDs)
#     + MDM (JTAG debug, software download via xsct/Vitis)
#     + LMB local memory (64 KB BRAM, runs the software)
#     + Clocking Wizard (50 MHz), proc_sys_reset
#
# Publishes dist/mb_led.bit / .ltx / .bin (project-named, like led_demo).
# Software: see src/main.c, build ELF with Vitis/xsct (scripts/build_elf.tcl).
#==============================================================================

set part          xc7k325tffg900-2
set proj_name     mb_led
set bd_name       system
set script_dir    [file dirname [info script]]
set root          [file normalize [file join $script_dir ..]]
set repo_root     [file normalize [file join $script_dir ../..]]
set src_dir       [file join $root src]
set proj_dir      [file join $root projects]

puts "=== MemBlaze MicroBlaze project: $proj_name (part $part) ==="

# ---------- fresh project ----------
if {[file exists $proj_dir]} { file delete -force $proj_dir }
create_project -force -dir $proj_dir -part $part $proj_name
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# ---------- block design: minimal MicroBlaze + AXI GPIO ----------
create_bd_design $bd_name

# 1) MicroBlaze (simplest: no caches, debug ON)
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze microblaze_0
set_property -dict [list \
    CONFIG.C_USE_DCACHE {0} \
    CONFIG.C_USE_ICACHE {0} \
    CONFIG.C_DEBUG_ENABLED {1} \
] [get_bd_cells microblaze_0]

# 2) automation on the MicroBlaze cell: local memory (64 KB BRAM) + MDM +
#    clocking wizard + proc_sys_reset + AXI periph interconnect (+ intc)
apply_bd_automation -rule xilinx.com:bd_rule:microblaze \
    -config {local_mem "64KB" ecc "Basic" debug_module "Debug Only" \
             axi_periph "1" axi_intc "0" clk "New Clocking Wizard (100 MHz)"} \
    [get_bd_cells microblaze_0]

# resolve the auto-created cells (names can be clk_wiz_0/1, mdm_0/1, ...)
set clk_cell [lindex [get_bd_cells -quiet -filter {VLNV =~ *clk_wiz*}] 0]
set mdm_cell [lindex [get_bd_cells -quiet -filter {VLNV =~ *mdm*}] 0]
if {$clk_cell eq ""} { error "clocking wizard not created by automation" }

# 2b) MDM: enable the JTAG UART (virtual serial console over JTAG).
#     C_INTERCONNECT=2 turns the MDM master into an S_AXI slave holding
#     the UART registers; its old master port disappears (periph M01 frees up).
set_property -dict [list \
    CONFIG.C_USE_UART {1} \
    CONFIG.C_INTERCONNECT {2} \
] [get_bd_cells $mdm_cell]

# 3) AXI GPIO: 3-bit output -> LEDs (the AXI interface that controls the LEDs)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_0
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {3} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_ALL_INPUTS {0} \
] [get_bd_cells axi_gpio_0]

# manual AXI-Lite wiring onto the periph interconnect that the MicroBlaze
# automation already created (microblaze M_AXI_DP -> periph S00_AXI;
# in 2024.2 the MDM also takes one master port, e.g. M01_AXI)
set periph [lindex [get_bd_cells -quiet -filter {VLNV =~ *axi_interconnect*}] 0]
set rst_cell [lindex [get_bd_cells -quiet -filter {VLNV =~ *proc_sys_reset*}] 0]
connect_bd_intf_net [get_bd_intf_pins ${periph}/M00_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins axi_gpio_0/s_axi_aclk]
connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins ${periph}/M00_ACLK]
connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn]
connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins ${periph}/M00_ARESETN]
# clock the (sometimes present) M01 master port used by the MDM
catch {connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins ${periph}/M01_ACLK]}
catch {connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins ${periph}/M01_ARESETN]}

# drive the system reset from the MDM debug reset (fixes proc_sys_reset
# EXT_LPF floating-input error at opt_design)
if {$mdm_cell ne ""} {
    catch {connect_bd_net [get_bd_pins ${mdm_cell}/Debug_SYS_Rst] [get_bd_pins ${rst_cell}/ext_reset_in]}
}

# 3b) MDM JTAG UART: its S_AXI slave hangs on the freed M01 master port
if {$mdm_cell ne ""} {
    connect_bd_intf_net [get_bd_intf_pins ${periph}/M01_AXI] [get_bd_intf_pins ${mdm_cell}/S_AXI]
    connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins ${mdm_cell}/S_AXI_ACLK]
    connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins ${mdm_cell}/S_AXI_ARESETN]
}

# 5) single-ended 50 MHz input clock from the board (D27)
set_property -dict [list \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ {50.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
    CONFIG.USE_RESET {false} \
] [get_bd_cells $clk_cell]
puts "clk_cell=$clk_cell clk pins: [get_bd_pins -quiet ${clk_cell}/clk_*]"
create_bd_port -dir I -type clk -freq_hz 50000000 sysclk
connect_bd_net [get_bd_ports sysclk] [get_bd_pins ${clk_cell}/clk_in1]
# feed the locked output to proc_sys_reset dcm_locked (avoids a driverless
# EXT_LPF net that opt_design turns into the LUT-I0 error)
set rst_cell [lindex [get_bd_cells -quiet -filter {VLNV =~ *proc_sys_reset*}] 0]
catch {connect_bd_net [get_bd_pins ${clk_cell}/locked] [get_bd_pins ${rst_cell}/dcm_locked]}

# 6) LEDs: 3-bit output port
create_bd_port -dir O -from 2 -to 0 led
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_ports led]

# 7) assign addresses + validate
assign_bd_address
validate_bd_design

# 8) wrapper as top + constraints
make_wrapper -files [get_files ${bd_name}.bd] -top
add_files -norecurse [file join [get_property DIRECTORY [current_project]] ${proj_name}.srcs sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
add_files -norecurse -fileset constrs_1 [file join $src_dir mb_led.xdc]
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# ---------- run flow ----------
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

# ---------- publish bit / ltx / bin to <repo_root>/dist/ ----------
set dist_dir [file join $repo_root dist]
file mkdir $dist_dir
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_src  [lindex [glob -nocomplain [file join $impl_dir *.bit]] 0]
set ltx_src  [lindex [glob -nocomplain [file join $impl_dir *.ltx]] 0]
set dcp_src  [lindex [glob -nocomplain [file join $impl_dir *_routed.dcp]] 0]

file copy -force $bit_src   [file join $dist_dir "$proj_name.bit"]
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

# ---------- export hardware platform (.xsa) for Vitis ----------
set xsa_file [file join $root "$proj_name.xsa"]
write_hw_platform -fixed -include_bit -force -file $xsa_file
puts "EXPORT: $xsa_file"

puts "=== DONE. dist/: $proj_name.bit / .ltx / .bin ; xsa: $xsa_file ==="
puts "=== Software: source mb_led/scripts/build_elf.tcl with xsct (Vitis) ==="