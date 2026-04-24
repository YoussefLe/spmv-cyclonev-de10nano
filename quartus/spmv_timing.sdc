# =============================================================================
# spmv_timing.sdc
# Contraintes de timing — DE10-Nano (Cyclone V 5CSEBA6U23I7)
# =============================================================================

create_clock -name clk_fpga -period 20.000 [get_ports {FPGA_CLK1_50}]

set_false_path -from [get_clocks {clk_fpga}] -to [get_clocks {*hps*}]
set_false_path -from [get_clocks {*hps*}]    -to [get_clocks {clk_fpga}]

# Multicycle for DSP MAC path (uncomment if needed at higher Fmax)
# set_multicycle_path -setup 2 -from [get_registers {*mac_product*}]
# set_multicycle_path -hold  1 -from [get_registers {*mac_product*}]
