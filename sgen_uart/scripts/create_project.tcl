#==============================================================================
# MemBlaze xc7k325tffg900-2 - sgen_uart ONE-CLICK build script
#
# Data path:
#   wave_gen (400 MHz, sine/ramp 16-bit) -> wbuf (dual-port BRAM)
#     -> reader (100 MHz, AXIS) -> axis_data_fifo (100 MHz)
#     -> AXI DMA S2MM -> acq BRAM (axi_bram_ctrl) -> MicroBlaze
#     -> JTAG UART -> PC visualization
#
# Run:
#   vivado -mode batch -source scripts/create_project.tcl
# Publishes dist/sgen_uart.bit/.bin + sgen_uart.xsa
# Software: scripts/build_elf.tcl (ELF), merge_elf.tcl (embed into bit/bin)
#==============================================================================

set part          xc7k325tffg900-2
set proj_name     sgen_uart
set top_module    sgen_uart_top
set bd_name       system
set script_dir    [file dirname [info script]]
set root          [file normalize [file join $script_dir ..]]
set repo_root     [file normalize [file join $script_dir ../..]]
set src_dir       [file join $root src]
set proj_dir      [file join $root projects]

puts "=== MemBlaze sgen_uart project: $proj_name (part $part) ==="

if {[file exists $proj_dir]} { file delete -force $proj_dir }
create_project -force -dir $proj_dir -part $part $proj_name
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

#------------------------------------------------------------------------------
# Block design
#------------------------------------------------------------------------------
create_bd_design $bd_name

# 1) MicroBlaze (simplest, debug ON)
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze microblaze_0
set_property -dict [list \
    CONFIG.C_USE_DCACHE {0} CONFIG.C_USE_ICACHE {0} CONFIG.C_DEBUG_ENABLED {1} \
] [get_bd_cells microblaze_0]

# 2) automation: 64KB local mem + MDM + clk_wiz(100M) + proc_sys_reset
#    (no periph interconnect - we add our own 2-master/4-slave one below)
apply_bd_automation -rule xilinx.com:bd_rule:microblaze \
    -config {local_mem "64KB" ecc "Basic" debug_module "Debug Only" \
             axi_periph "0" axi_intc "0" clk "New Clocking Wizard (100 MHz)"} \
    [get_bd_cells microblaze_0]
set_property CONFIG.C_D_AXI {1} [get_bd_cells microblaze_0]

set clk_cell [lindex [get_bd_cells -quiet -filter {VLNV =~ *clk_wiz*}] 0]
set mdm_cell [lindex [get_bd_cells -quiet -filter {VLNV =~ *mdm*}] 0]
set rst_cell [lindex [get_bd_cells -quiet -filter {VLNV =~ *proc_sys_reset*}] 0]
if {$clk_cell eq "" || $mdm_cell eq ""} { error "automation cells not found" }

# 3) MDM: JTAG UART on (S_AXI holds the UART registers)
set_property -dict [list CONFIG.C_USE_UART {1} CONFIG.C_INTERCONNECT {2}] \
    [get_bd_cells $mdm_cell]

# 4) clocking: 50 MHz in; 100 MHz (MB/AXI/FIFO/DMA) + 400 MHz (wave_gen)
set_property -dict [list \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIM_IN_FREQ {50.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {400.000} \
    CONFIG.USE_RESET {false} \
] [get_bd_cells $clk_cell]
create_bd_port -dir I -type clk -freq_hz 50000000 sysclk
connect_bd_net [get_bd_ports sysclk] [get_bd_pins ${clk_cell}/clk_in1]
catch {connect_bd_net [get_bd_pins ${clk_cell}/locked] [get_bd_pins ${rst_cell}/dcm_locked]}
# bring both clocks out
create_bd_port -dir O -type clk wgen_clk
connect_bd_net [get_bd_pins ${clk_cell}/clk_out2] [get_bd_ports wgen_clk]
create_bd_port -dir O -type clk clk_100
connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_ports clk_100]

# 5) AXI GPIO: control/status for the waveform engine
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_0
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {4}  CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_IS_DUAL    {1} \
    CONFIG.C_GPIO2_WIDTH {2} CONFIG.C_ALL_INPUTS_2 {1} \
] [get_bd_cells axi_gpio_0]
create_bd_port -dir O -from 3 -to 0 ctrl
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_ports ctrl]
create_bd_port -dir I -from 1 -to 0 sts
connect_bd_net [get_bd_ports sts] [get_bd_pins axi_gpio_0/gpio2_io_i]

# 6) acquisition BRAM (AXI slave, 32-bit x 4096 = 16KB, defaults are fine)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl axi_bram_ctrl_0

# 7) AXI DMA: S2MM only, 16-bit AXIS in, 32-bit MM out (parameters use the
#    lowercase c_* names of the 2024.2 axi_dma)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0
set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_micro_dma {1} \
    CONFIG.c_single_interface {1} \
] [get_bd_cells axi_dma_0]

# 8) AXIS FIFO: 32-bit (4 bytes) tdata, 1024 deep, 100 MHz
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axis_data_fifo_0
set_property -dict [list \
    CONFIG.FIFO_DEPTH {1024} \
    CONFIG.TDATA_NUM_BYTES {4} \
] [get_bd_cells axis_data_fifo_0]

# 9) our own interconnect: 2 slaves (MB + DMA data) x 4 masters
#    (fresh axi_interconnect instances allow NUM_SI/NUM_MI; automation ones
#     are read-only) - MB M_AXI_DP, DMA S2MM, gpio, dma-lite, mdm-uart, bram
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect ic_axi
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {4}] [get_bd_cells ic_axi]

connect_bd_intf_net [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins ic_axi/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM]  [get_bd_intf_pins ic_axi/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins ic_axi/M00_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ic_axi/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ic_axi/M02_AXI] [get_bd_intf_pins ${mdm_cell}/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ic_axi/M03_AXI] [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]

# clocks / resets (100 MHz domain everywhere)
connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins ic_axi/ACLK]
connect_bd_net [get_bd_pins ${rst_cell}/interconnect_aresetn] [get_bd_pins ic_axi/ARESETN]
foreach p {S00 S01 M00 M01 M02 M03} {
    connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins ic_axi/${p}_ACLK]
    connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins ic_axi/${p}_ARESETN]
}

# --- peripheral clocks / resets ---
catch {connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins axi_gpio_0/s_axi_aclk]}
catch {connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn]}

catch {connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins axi_bram_ctrl_0/s_axi_aclk]}
catch {connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn]}

catch {connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins axi_dma_0/s_axi_lite_aclk]}
catch {connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins axi_dma_0/axi_resetn]}
catch {connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]}

# --- FIFO: stream from the custom reader (external AXIS port), to the DMA ---
catch {connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins axis_data_fifo_0/s_axis_aclk]}
catch {connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins axis_data_fifo_0/s_axis_aresetn]}
connect_bd_intf_net [get_bd_intf_pins axis_data_fifo_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
# external AXI-Stream slave interface (reader drives it from top.v)
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis
connect_bd_intf_net [get_bd_intf_ports s_axis] [get_bd_intf_pins axis_data_fifo_0/S_AXIS]

# --- MDM debug reset -> system reset, and MDM UART S_AXI clock/reset ----
if {$mdm_cell ne ""} {
    catch {connect_bd_net [get_bd_pins ${mdm_cell}/Debug_SYS_Rst] [get_bd_pins ${rst_cell}/ext_reset_in]}
    catch {connect_bd_net [get_bd_pins ${clk_cell}/clk_out1] [get_bd_pins ${mdm_cell}/S_AXI_ACLK]}
    catch {connect_bd_net [get_bd_pins ${rst_cell}/peripheral_aresetn] [get_bd_pins ${mdm_cell}/S_AXI_ARESETN]}
}

# 10) addresses (MB space: gpio/dma-lite/mdm/bram; the DMA writes the same
#     axi_bram_ctrl segment via its 0x80000000 window)
assign_bd_address
# IMPORTANT: make the DMA's S2MM window on the acq BRAM sit at 0xC0000000
# (same address the firmware programs into the S2MM descriptor) - otherwise
# the DMA write lands in an unmapped hole of ITS address space and the BRAM
# never receives data.
set dma_sp [get_bd_addr_spaces -quiet axi_dma_0/Data_S2MM]
if {$dma_sp ne ""} {
    set seg_found ""
    foreach s [get_bd_addr_segs -quiet -of_objects $dma_sp] {
        if {[string match *axi_bram_ctrl* [get_property NAME $s]]} { set seg_found $s }
    }
    if {$seg_found eq ""} {
        create_bd_addr_seg -range 0x2000 -offset 0xC0000000 $dma_sp \
            [get_bd_addr_segs axi_bram_ctrl_0/S_AXI/Reg] SEG_axi_bram_ctrl_0_Mem0
    } else {
        set_property offset 0xC0000000 [get_bd_addr_segs $seg_found]
    }
    puts "DMA window on acq BRAM: $seg_found @0xC0000000"
}

validate_bd_design

# 11) wrapper + sources + constraints
make_wrapper -files [get_files ${bd_name}.bd] -top
add_files -norecurse [file join [get_property DIRECTORY [current_project]] ${proj_name}.srcs sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
foreach f {top.v wave_gen.v wbuf.v reader.v} {
    add_files -norecurse -fileset sources_1 [file join $src_dir $f]
}
add_files -norecurse -fileset constrs_1 [file join $src_dir ${proj_name}.xdc]
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
# Publish bit / ltx / bin + xsa
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

set xsa_file [file join $root "$proj_name.xsa"]
write_hw_platform -fixed -include_bit -force -file $xsa_file
puts "EXPORT: $xsa_file"
puts "=== DONE. dist/$proj_name.bit/.bin ; xsa: $xsa_file ==="
puts "=== Software: xsct.bat scripts/build_elf.tcl, then merge_elf.tcl ==="