create_project -force -dir D:/work2026/ai/opencode/memblaze_demo/sgen_uart/_probe projects/probe -part xc7k325tffg900-2
create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect ic2
puts "ic2 default S ports: [get_bd_intf_pins -quiet ic2/S*_AXI]"
puts "ic2 default M ports: [get_bd_intf_pins -quiet ic2/M*_AXI]"
catch {set_property CONFIG.NUM_SI {2} [get_bd_cells ic2]} r1
puts "set NUM_SI: $r1"
catch {set_property CONFIG.NUM_MI {3} [get_bd_cells ic2]} r2
puts "set NUM_MI: $r2"
puts "S after: [get_bd_intf_pins -quiet ic2/S*_AXI]"
puts "M after: [get_bd_intf_pins -quiet ic2/M*_AXI]"
puts "PROBE13_DONE"