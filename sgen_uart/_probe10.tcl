create_project -force -dir D:/work2026/ai/opencode/memblaze_demo/sgen_uart/_probe projects/probe -part xc7k325tffg900-2
create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze microblaze_0
set_property -dict [list CONFIG.C_USE_DCACHE {0} CONFIG.C_USE_ICACHE {0} CONFIG.C_DEBUG_ENABLED {1}] [get_bd_cells microblaze_0]
apply_bd_automation -rule xilinx.com:bd_rule:microblaze \
    -config {local_mem "64KB" ecc "Basic" debug_module "Debug Only" \
             axi_periph "1" axi_intc "0" clk "New Clocking Wizard (100 MHz)"} \
    [get_bd_cells microblaze_0]
set periph [lindex [get_bd_cells -quiet -filter {VLNV =~ *axi_interconnect*}] 0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axis_data_fifo_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl axi_bram_ctrl_0

puts "=== automate gpio (MB only) ==="
catch {apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master {/microblaze_0/M_AXI_DP} Clk {Auto}} [get_bd_intf_pins axi_gpio_0/S_AXI]} r1
puts "gpio: $r1"
puts "=== automate dma lite (MB only) ==="
catch {apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master {/microblaze_0/M_AXI_DP} Clk {Auto}} [get_bd_intf_pins axi_dma_0/S_AXI_LITE]} r2
puts "dma: $r2"
puts "=== automate bram (MB + DMA master) ==="
catch {apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master {/microblaze_0/M_AXI_DP /axi_dma_0/M_AXI_S2MM} Clk {Auto}} [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]} r3
puts "bram: $r3"
puts "periph M ports: [get_bd_intf_pins -quiet ${periph}/M*_AXI]"
puts "periph S ports: [get_bd_intf_pins -quiet ${periph}/S*_AXI]"
puts "PROBE10_DONE"