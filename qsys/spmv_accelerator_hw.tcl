# =============================================================================
# spmv_accelerator_hw.tcl
# Description de composant pour Platform Designer (Qsys)
# Cyclone V DE10-Nano — SpMV Accelerator IP
# =============================================================================

package require -exact qsys 16.0

set_module_property DESCRIPTION "SpMV Accelerator for GNN (Int8/Int32, CSR format)"
set_module_property NAME spmv_accelerator
set_module_property VERSION 1.0
set_module_property GROUP "Custom IP/Accelerators"
set_module_property AUTHOR "Green AI Lab"
set_module_property DISPLAY_NAME "SpMV GNN Accelerator"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL spmv_accelerator
add_fileset_file spmv_pkg.vhd         VHDL PATH hdl/spmv_pkg.vhd
add_fileset_file spmv_accelerator.vhd VHDL PATH hdl/spmv_accelerator.vhd

add_fileset SIM_VHDL SIM_VHDL "" ""
set_fileset_property SIM_VHDL TOP_LEVEL spmv_accelerator
add_fileset_file spmv_pkg.vhd         VHDL PATH hdl/spmv_pkg.vhd
add_fileset_file spmv_accelerator.vhd VHDL PATH hdl/spmv_accelerator.vhd

add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
add_interface_port reset reset_n reset_n Input 1

add_interface avs avalon end
set_interface_property avs addressUnits WORDS
set_interface_property avs associatedClock clock
set_interface_property avs associatedReset reset
set_interface_property avs bridgedAddressOffset 0
set_interface_property avs readLatency 1
set_interface_property avs readWaitTime 0
set_interface_property avs writeWaitTime 0
set_interface_property avs timingUnits Cycles

add_interface_port avs avs_address    address    Input  4
add_interface_port avs avs_read       read       Input  1
add_interface_port avs avs_readdata   readdata   Output 32
add_interface_port avs avs_write      write      Input  1
add_interface_port avs avs_writedata  writedata  Input  32
add_interface_port avs avs_waitrequest waitrequest Output 1

add_interface avm avalon start
set_interface_property avm addressUnits SYMBOLS
set_interface_property avm associatedClock clock
set_interface_property avm associatedReset reset
set_interface_property avm burstOnBurstBoundariesOnly false
set_interface_property avm doStreamReads false
set_interface_property avm doStreamWrites false
set_interface_property avm linewrapBursts false

add_interface_port avm avm_address       address       Output 32
add_interface_port avm avm_read          read          Output 1
add_interface_port avm avm_readdata      readdata      Input  32
add_interface_port avm avm_readdatavalid readdatavalid Input  1
add_interface_port avm avm_write         write         Output 1
add_interface_port avm avm_writedata     writedata     Output 32
add_interface_port avm avm_waitrequest   waitrequest   Input  1
add_interface_port avm avm_byteenable    byteenable    Output 4
add_interface_port avm avm_burstcount    burstcount    Output 4
