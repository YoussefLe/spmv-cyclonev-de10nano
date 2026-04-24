---
license: mit
tags:
  - fpga
  - cyclone-v
  - de10-nano
  - spmv
  - gnn
  - green-ai
  - vhdl
  - avalon-mm
  - embedded
---

# SpMV FPGA Accelerator — Cyclone V DE10-Nano

**Accélérateur matériel Sparse Matrix-Vector Multiply (SpMV)** pour GNN (Dataset Cora) sur SoC Cyclone V.

- **Architecture** : Avalon-MM Slave (registres HPS) + Avalon-MM Master (DMA SDRAM) + FSM 16 états + DSP MAC
- **Quantification** : Int8 entrées × Int8 → Int32 accumulation
- **Format** : CSR (Compressed Sparse Row)
- **Optimisation** : 4 × Int8 packés par mot 32-bit bus

## Quick Start

```bash
# 1. Simulation (ModelSim)
vcom -2008 hdl/spmv_pkg.vhd hdl/spmv_accelerator.vhd hdl/spmv_tb.vhd
vsim work.spmv_tb -do "run 10 us"

# 2. Cross-compile driver
cd sw/ && make arm

# 3. Deploy to DE10-Nano
./scripts/deploy_de10nano.sh 192.168.1.xxx
```

## Files

| File | Description |
|------|-------------|
| `hdl/spmv_pkg.vhd` | Constants, types, FSM states |
| `hdl/spmv_accelerator.vhd` | Main IP: Avalon Slave + Master + FSM + MAC |
| `hdl/spmv_tb.vhd` | Testbench (3×3 matrix, auto-check) |
| `sw/spmv_hps_driver.cpp` | C++ Linux driver (mmap /dev/mem) |
| `qsys/spmv_accelerator_hw.tcl` | Platform Designer component |
| `quartus/spmv_timing.sdc` | Timing constraints |
| `dts/spmv_overlay.dts` | Device Tree Overlay |
| `scripts/deploy_de10nano.sh` | Automated deployment script |

## Full Guide

See [GUIDE_EXECUTION.md](GUIDE_EXECUTION.md) for the complete 10-step walkthrough.
