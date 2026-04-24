# ═══════════════════════════════════════════════════════════════════════════════
#  GUIDE D'EXÉCUTION COMPLET — Accélérateur SpMV pour GNN sur DE10-Nano
#  Green AI — Cyclone V SoC — Int8/Int32 quantifié
# ═══════════════════════════════════════════════════════════════════════════════

## Table des matières
1. [Prérequis](#1-prérequis)
2. [Structure du projet](#2-structure-du-projet)
3. [Étape 1 — Créer le projet Quartus Prime](#3-étape-1--créer-le-projet-quartus-prime)
4. [Étape 2 — Configurer Platform Designer (Qsys)](#4-étape-2--configurer-platform-designer-qsys)
5. [Étape 3 — Intégrer l'IP SpMV](#5-étape-3--intégrer-lip-spmv)
6. [Étape 4 — Synthèse et Place & Route](#6-étape-4--synthèse-et-place--route)
7. [Étape 5 — Simulation fonctionnelle (ModelSim)](#7-étape-5--simulation-fonctionnelle-modelsim)
8. [Étape 6 — Compilation croisée du driver C++](#8-étape-6--compilation-croisée-du-driver-c)
9. [Étape 7 — Préparer la carte SD (Linux)](#9-étape-7--préparer-la-carte-sd-linux)
10. [Étape 8 — Déployer et exécuter](#10-étape-8--déployer-et-exécuter)
11. [Étape 9 — Vérification et debug](#11-étape-9--vérification-et-debug)
12. [Étape 10 — Métriques Green AI](#12-étape-10--métriques-green-ai)
13. [Diagramme d'architecture](#13-diagramme-darchitecture)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prérequis

### Logiciels (PC hôte)
| Logiciel | Version | Usage |
|----------|---------|-------|
| Intel Quartus Prime Lite | ≥ 20.1 | Synthèse FPGA |
| Platform Designer (Qsys) | inclus dans Quartus | Interconnect SoC |
| ModelSim Intel FPGA | inclus dans Quartus | Simulation VHDL |
| SoC EDS (Embedded Design Suite) | ≥ 20.1 | Toolchain ARM + preloader |
| Linaro GCC ARM | 7.5+ | Cross-compilation C++ |

### Matériel
| Composant | Spécification |
|-----------|--------------|
| DE10-Nano | Cyclone V 5CSEBA6U23I7 |
| Carte microSD | ≥ 8 Go, Class 10 |
| Câble USB | Micro-B (UART console) |
| Câble Ethernet | Pour SSH (ou WiFi USB) |
| Alimentation | 5V / 2A via barrel jack |

### Image Linux
- Utiliser l'image officielle Terasic **DE10-Nano-Ubuntu** ou **DE10-Nano-Yocto**
- Ou construire une image custom avec Buildroot/Yocto

---

## 2. Structure du projet

```
spmv_de10nano/
├── hdl/
│   ├── spmv_pkg.vhd              # Package constantes & types
│   ├── spmv_accelerator.vhd      # IP principale (Slave + Master + FSM)
│   └── spmv_tb.vhd               # Testbench
├── qsys/
│   └── spmv_accelerator_hw.tcl   # Description Platform Designer
├── quartus/
│   └── spmv_timing.sdc           # Contraintes timing
├── dts/
│   └── spmv_overlay.dts          # Device Tree Overlay
├── sw/
│   ├── spmv_hps_driver.cpp       # Driver C++ HPS
│   └── Makefile                  # Cross-compilation
├── scripts/
│   └── deploy_de10nano.sh        # Script de déploiement
├── GUIDE_EXECUTION.md            # Ce fichier
└── README.md
```

---

## 3. Étape 1 — Créer le projet Quartus Prime

### 3.1 Nouveau projet
```
File → New Project Wizard
  - Répertoire : ~/spmv_de10nano/quartus/
  - Nom        : soc_system
  - Top-level  : soc_system
```

### 3.2 Sélection du FPGA
```
Family  : Cyclone V
Device  : 5CSEBA6U23I7
Package : UBGA (484 pins)
Speed   : 7 (slowest, pour timing margin)
```

### 3.3 Importer le projet de base DE10-Nano
```bash
git clone https://github.com/terasic/de10-nano-soc.git
cp de10-nano-soc/hw/quartus/soc_system.qsys quartus/
```

> **Important** : Le fichier `soc_system.qsys` de Terasic contient déjà le HPS configuré avec les bridges H2F, LW-H2F, et F2H-SDRAM. On va y AJOUTER notre IP.

---

## 4. Étape 2 — Configurer Platform Designer (Qsys)

### 4.1 Ouvrir Platform Designer
```
Tools → Platform Designer → Ouvrir : quartus/soc_system.qsys
```

### 4.2 Composants existants
```
┌─────────────────────────────────────────────┐
│  hps_0 (HPS Intel Cyclone V)               │
│  ├── h2f_lw_axi_master  (LW H2F bridge)    │  ← registres IP
│  ├── h2f_axi_master     (full H2F bridge)   │
│  ├── f2h_sdram0_data    (F2H SDRAM)         │  ← IP Master → SDRAM
│  └── h2f_reset                              │
├─────────────────────────────────────────────┤
│  clk_0 (50 MHz oscillateur)                │
└─────────────────────────────────────────────┘
```

### 4.3 Ajouter l'IP SpMV

```
1. IP Catalog → "Add IP Search Path" → ../qsys/
2. Chercher "spmv" → Double-clic "SpMV GNN Accelerator" → spmv_0

3. Connexions (CRITIQUE) :
   ┌────────────────────────────┬──────────────────────────────────┐
   │  Port spmv_0               │  Connecter à                    │
   ├────────────────────────────┼──────────────────────────────────┤
   │  clock (clock sink)        │  clk_0.clk                      │
   │  reset (reset sink)        │  hps_0.h2f_reset                │
   │  avs   (Avalon Slave)      │  hps_0.h2f_lw_axi_master       │
   │  avm   (Avalon Master)     │  hps_0.f2h_sdram0_data          │
   └────────────────────────────┴──────────────────────────────────┘
```

### 4.4 Adresse mémoire esclave
```
Address Map :
  spmv_0.avs → Base: 0x0000_0000  End: 0x0000_003F → Lock
```

> Adresse physique HPS = `0xFF20_0000` (LW H2F base) + `0x0000_0000` (IP offset)

### 4.5 Port F2H SDRAM
```
Double-clic hps_0 → FPGA-to-HPS SDRAM : ☑ f2h_sdram0 → Width: 32-bit
```

### 4.6 Générer
```
Generate → Generate HDL... → Synthesis: VHDL → Generate
```

---

## 5. Étape 3 — Intégrer l'IP SpMV

```vhdl
-- Top-level wrapper :
u0 : component soc_system
  port map (
    clk_clk       => FPGA_CLK1_50,
    reset_reset_n => '1',
    -- ... autres ports HPS
  );
```

Ajouter au projet : `hdl/spmv_pkg.vhd`, `hdl/spmv_accelerator.vhd`, fichiers Qsys, `spmv_timing.sdc`.

---

## 6. Étape 4 — Synthèse et Place & Route

```
Processing → Start Compilation (Ctrl+L)
```

**Ressources attendues** : ~800 ALMs, ~600 registres, 1 DSP block, Fmax > 100 MHz

```
File → Convert Programming Files... → RBF → Generate
```

---

## 7. Étape 5 — Simulation (ModelSim)

```bash
vlib work
vcom -2008 hdl/spmv_pkg.vhd
vcom -2008 hdl/spmv_accelerator.vhd
vcom -2008 hdl/spmv_tb.vhd
vsim -t 1ns work.spmv_tb
add wave sim:/spmv_tb/dut/state sim:/spmv_tb/dut/accumulator
run 10 us
```

Résultat attendu : Y = [5, 18, 23] ✓

---

## 8. Étape 6 — Cross-compilation C++

```bash
sudo apt install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
cd sw/ && make arm
file spmv_driver_arm  # ELF 32-bit ARM
```

---

## 9. Étape 7 — Carte SD

Partitions : FAT32 (boot: zImage + dtb + spmv.rbf) / ext4 (rootfs) / raw (preloader)

Bootargs : `mem=768M` pour réserver 0x30000000+ au FPGA.

---

## 10. Étape 8 — Déployer et exécuter

```bash
# Automatique :
./scripts/deploy_de10nano.sh 192.168.1.xxx

# Manuel :
scp soc_system.rbf root@IP:/root/spmv.rbf
scp spmv_driver_arm root@IP:/root/spmv_driver
ssh root@IP
echo spmv.rbf > /sys/class/fpga_manager/fpga0/firmware
echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable
echo 1 > /sys/class/fpga-bridge/hps2fpga/enable
echo 1 > /sys/class/fpga-bridge/fpga2hps/enable
./spmv_driver          # test 3×3
./spmv_driver --cora   # Cora 2708 nœuds
```

---

## 11. Étape 9 — Debug

```bash
devmem2 0xFF200000 w   # REG_CTRL
devmem2 0x30040000 w   # Y[0]
```

SignalTap : trigger sur `start_pulse = '1'`, observer `state`, `avm_address`, `accumulator`.

---

## 12. Étape 10 — Métriques Green AI

Le driver affiche automatiquement : cycles FPGA, speedup, estimation énergie.

| Plateforme | Temps | Power | Énergie | Coût |
|-----------|-------|-------|---------|------|
| FPGA CV | ~0.1 ms | ~3 W | ~0.3 mJ | ~130 € |
| ARM A9 | ~0.5 ms | ~2 W | ~1.0 mJ | (inclus) |
| GPU (T4) | ~0.01ms | ~70 W | ~0.7 mJ | ~2000 € |

---

## 13. Diagramme d'architecture

```
    ┌─────────────────────────────────────────────────────────────┐
    │                     DE10-Nano SoC                           │
    │  ┌──────────────────────┐    ┌──────────────────────────┐  │
    │  │    HPS (ARM A9)      │    │    FPGA Fabric            │  │
    │  │  ┌────────────────┐  │    │  ┌──────────────────────┐ │  │
    │  │  │ Linux (driver) │──╋────╋──│ Avalon Slave (regs)  │ │  │
    │  │  │ mmap /dev/mem  │  │ LW │  │         ↓            │ │  │
    │  │  └────────────────┘  │ H2F│  │  FSM (16 états)      │ │  │
    │  │                      │    │  │         ↓            │ │  │
    │  │                      │    │  │  Avalon Master (DMA) │ │  │
    │  │                      │    │  │         ↓            │ │  │
    │  │                      │    │  │  DSP: Int8×Int8→Int32│ │  │
    │  │                      │    │  └──────────────────────┘ │  │
    │  └──────────┬───────────┘    └────────────┬──────────────┘  │
    │             └─────────── SDRAM ────────────┘ F2H SDRAM      │
    │                    0x30000000: row_ptr/col_ind/values/X/Y   │
    └─────────────────────────────────────────────────────────────┘
```

---

## 14. Troubleshooting

| Problème | Solution |
|----------|----------|
| `mmap: Permission denied` | Exécuter en root |
| DONE ne passe pas à 1 | `echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable` |
| Résultats Y faux | Vérifier connexion `avm → f2h_sdram0_data` dans Qsys |
| VHDL ne compile pas | Utiliser `vcom -2008` |
| Bus error mmap | Ajouter `mem=768M` aux bootargs |
