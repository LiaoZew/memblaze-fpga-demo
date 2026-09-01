create_project -force -dir D:/work2026/ai/opencode/memblaze_demo/sgen_uart/_probe projects/probe -part xc7k325tffg900-2
create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze microblaze_0
set_property -dict [list CONFIG.C_USE_DCACHE {0} CONFIG.C_USE_ICACHE {0} CONFIG.C_DEBUG_ENABLED {1}] [get_bd_cells microblaze_0]
apply_bd_automation -rule xilinx.com:bd_rule:microblaze \
    -config {local_mem "64KB" ecc "Basic" debug_module "Debug Only" \
             axi_periph "1" axi_intc "0" clk "New Clocking Wizard (100 MHz)"} \
    [get_bd_cells microblaze_0]
set periph [lindex [get_bd_cells -quiet -filter {VLNV =~ *axi_interconnect*}] 0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axis_data_fifo_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl axi_bram_ctrl_0

puts "=== periph intf pins now ==="
puts [get_bd_intf_pins -quiet ${periph}/M*_AXI]
puts "=== try create_bd_intf_pin S01/M02/M03 ==="
catch {create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 ${periph}/S01_AXI} r1
puts "S01: $r1"
catch {create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 ${periph}/M02_AXI} r2
catch {create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 ${periph}/M03_AXI} r3
puts "M02: $r2  M03: $r3"
puts "after: [get_bd_intf_pins -quiet ${periph}/M*_AXI]  ${periph}/S*_AXI=[get_bd_intf_pins -quiet ${periph}/S*_AXI]"
puts "=== axi_dma CONFIG params ==="
puts [lsort [regexp -all -inline {CONFIG\.C_[A-Z0-9_]+} [report_property -return_string -all [get_bd_cells axi_dma_0]]]]
puts "=== axis_data_fifo CONFIG params ==="
puts [lsort [regexp -all -inline {CONFIG\.C_[A-Z0-9_]+} [report_property -return_string -all [get_bd_cells axis_data_fifo_0]]]]
puts "=== axi_bram_ctrl CONFIG params ==="
puts [lsort [regexp -all -inline {CONFIG\.C_[A-Z0-9_]+} [report_property -return_string -all [get_bd_cells axi_bram_ctrl_0]]]]
puts "PROBE9_DONE"