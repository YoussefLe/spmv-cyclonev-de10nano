# 📦 Fichiers à ajouter dans Quartus — Guide Complet

## Architecture du projet

```
de10nano_spmv/                          ← Dossier projet Quartus
├── spmv_top.vhd                        ← TOP LEVEL (nouveau !)
├── hdl/
│   ├── spmv_pkg.vhd                    ← Package types/constantes
│   └── spmv_accelerator.vhd            ← IP SpMV
├── qsys/
│   └── spmv_accelerator_hw.tcl         ← Composant Platform Designer
├── quartus/
│   └── spmv_timing.sdc                 ← Contraintes timing
├── soc_system/                          ← Auto-généré par Platform Designer
│   ├── soc_system.qsys
│   ├── soc_system.sopcinfo
│   └── soc_system/synthesis/...         ← Fichiers HDL générés
└── output_files/
    └── spmv_top.sof / .rbf             ← Sortie compilation
```

---

## 🔧 Étape 1 : Créer le projet Quartus

1. **File → New Project Wizard**
2. Dossier : `C:\de10nano_spmv`  (ou votre chemin)
3. Nom du projet : `spmv_top`
4. **Top-level entity** : `spmv_top`
5. Device : **5CSEBA6U23I7** (Cyclone V SE, family = Cyclone V)

---

## 🔧 Étape 2 : Construire le système Platform Designer (Qsys)

1. **Tools → Platform Designer**
2. Créer un nouveau système nommé **`soc_system`**
3. Ajouter les composants suivants :
### Composants à ajouter dans Platform Designer :
| # | Composant | Instance Name | Connexions |
|---|-----------|---------------|------------|
| 1 | **Clock Source** | `clk_0` | `clk` = 50 MHz, exporté |
| 2 | **Arria/Cyclone V HPS** | `hps_0` | Voir config ci-dessous |
| 3 | **SpMV Accelerator** | `spmv_0` | Voir connexions ci-dessous |

### Configuration du HPS (`hps_0`) :
**Onglet SDRAM :**
- DDR3, 32-bit, 400 MHz (standard DE10-Nano)
**Onglet Peripheral Pins :**
- EMAC1 : RGMII
- SDIO : 4-bit
- USB1 : Enabled  
- UART0 : Enabled
- I2C0, I2C1 : Enabled
- SPI Master 1 : Enabled
- GPIO : 09, 35, 40, 53, 54, 61
**Onglet FPGA Interfaces :**
- ✅ **Lightweight HPS-to-FPGA** (LW H2F) — 32-bit, pour les registres de l'IP
- ✅ **FPGA-to-HPS SDRAM** (F2H SDRAM0) — 32-bit, pour le DMA master
- ❌ HPS-to-FPGA (full) — pas nécessaire
### Ajout de l'IP SpMV dans Platform Designer :
1. **IP Catalog → New Component** (ou importer le .tcl)
2. **Tools → Options → IP Search Path** : ajouter le dossier `qsys/`
3. Le composant `SpMV GNN Accelerator` apparaît dans le catalogue sous `Custom IP/Accelerators`
4. L'ajouter au système, instance name : `spmv_0`

### Connexions dans Platform Designer :

```
clk_0.clk              → hps_0.f2h_sdram0_clock
clk_0.clk              → spmv_0.clock
clk_0.clk_reset        → spmv_0.reset
hps_0.h2f_lw_avm       → spmv_0.avs        (base: 0x0000_0000, span 64B)
spmv_0.avm             → hps_0.f2h_sdram0_data
hps_0.memory           → exporté (memory)
hps_0.hps_io           → exporté (hps_io)
```

**Résumé des connexions visuelles :**
```
   ┌──────────┐           ┌──────────────────┐
   │  clk_0   │──clk──────│  hps_0           │
   │ (50MHz)  │──reset────│  (Cyclone V HPS) │
   └──────────┘     │     │                  │
                    │     │  h2f_lw_avm ─────┼──── Avalon Slave ──→ spmv_0.avs
                    │     │                  │                       (registres)
                    │     │  f2h_sdram0_data─┼──── Avalon Master ←─ spmv_0.avm
                    │     │                  │                       (DMA SDRAM)
                    │     │  memory ─────────┼──── exporté → DDR3
                    │     │  hps_io ─────────┼──── exporté → pins HPS
                    │     └──────────────────┘
                    │
                    └──── clk ──→ spmv_0.clock
                          reset ──→ spmv_0.reset
```

4. **Assign Base Addresses** : `System → Assign Base Addresses` (auto)
   - `spmv_0.avs` sera à offset 0x0 dans l'espace LW H2F (= 0xFF20_0000 côté HPS)
5. **Generate HDL** : `Generate → Generate HDL`, Synthesis = VHDL, répertoire = `soc_system/`

---

## 🔧 Étape 3 : Ajouter les fichiers dans Quartus

### Menu : **Project → Add/Remove Files in Project**

Ajoutez ces fichiers **dans cet ordre** (l'ordre compte pour les packages VHDL) :

| # | Fichier | Type | Rôle |
|---|---------|------|------|
| 1 | `soc_system/synthesis/soc_system.qip` | QIP | Système Qsys auto-généré (inclut TOUT le HPS + interconnect + votre IP) |
| 2 | `hdl/spmv_pkg.vhd` | VHDL | Package (constantes, types FSM) — **doit être avant spmv_accelerator et spmv_top** |
| 3 | `hdl/spmv_accelerator.vhd` | VHDL | IP SpMV |
| 4 | `hdl/spmv_top.vhd` | VHDL | **TOP LEVEL** |
| 5 | `quartus/spmv_timing.sdc` | SDC | Contraintes timing |

### ⚠️ Points importants :

- Le fichier `.qip` (étape 1) est **auto-généré** par Platform Designer. Il inclut déjà `spmv_pkg.vhd` et `spmv_accelerator.vhd` via le TCL. **Mais** il les cherche dans le chemin relatif du TCL (`hdl/`). Si vous avez des conflits, ajoutez seulement le `.qip` + `spmv_top.vhd` + `.sdc`.
- **Ne pas ajouter** `spmv_tb.vhd` (testbench = simulation uniquement, pas synthèse).
- **Ne pas ajouter** les fichiers `sw/` (C++, c'est pour le HPS Linux).

### Configuration minimale si le .qip inclut déjà les fichiers HDL :

| # | Fichier | Obligatoire |
|---|---------|-------------|
| 1 | `soc_system/synthesis/soc_system.qip` | ✅ Oui |
| 2 | `hdl/spmv_top.vhd` | ✅ Oui |
| 3 | `quartus/spmv_timing.sdc` | ✅ Oui |

(Le `.qip` tire automatiquement `spmv_pkg.vhd` et `spmv_accelerator.vhd`)

---

## 🔧 Étape 4 : Vérifier le Top Level

**Assignments → Settings → General → Top-level entity** : `spmv_top`

Ou via TCL console :
```tcl
set_global_assignment -name TOP_LEVEL_ENTITY spmv_top
```

---

## 🔧 Étape 5 : Pin Assignments (DE10-Nano)

Les pins HPS (DDR3, Ethernet, USB, etc.) sont **automatiquement assignées** par le HPS megafunction — vous n'avez rien à faire pour elles.

Les pins FPGA (clocks, LEDs, keys, switches) doivent être assignées. Utilisez le fichier `.qsf` standard DE10-Nano :

```tcl
# ======================== Clocks ========================
set_location_assignment PIN_V11  -to FPGA_CLK1_50
set_location_assignment PIN_Y13  -to FPGA_CLK2_50
set_location_assignment PIN_E11  -to FPGA_CLK3_50
# ======================== LEDs ========================
set_location_assignment PIN_W15  -to LED[0]
set_location_assignment PIN_AA24 -to LED[1]
set_location_assignment PIN_V16  -to LED[2]
set_location_assignment PIN_V15  -to LED[3]
set_location_assignment PIN_AF26 -to LED[4]
set_location_assignment PIN_AE26 -to LED[5]
set_location_assignment PIN_Y16  -to LED[6]
set_location_assignment PIN_AA23 -to LED[7]
# ======================== Keys ========================
set_location_assignment PIN_AH17 -to KEY[0]
set_location_assignment PIN_AH16 -to KEY[1]
# ======================== Switches ========================
set_location_assignment PIN_L10  -to SW[0]
set_location_assignment PIN_L9   -to SW[1]
set_location_assignment PIN_H6   -to SW[2]
set_location_assignment PIN_H5   -to SW[3]
# ======================== IO Standard ========================
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to FPGA_CLK1_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[*]
```

→ Copiez ces lignes dans votre fichier `spmv_top.qsf` ou via **Assignments → Assignment Editor**.

---

## 🔧 Étape 6 : Compilation

### Ordre des opérations :
```
1. Platform Designer → Generate HDL    (génère soc_system/)
2. Quartus → Processing → Start Compilation
   └── Analysis & Synthesis
   └── Fitter (Place & Route)
   └── Assembler (génère .sof)
   └── Timing Analyzer
```

### Via TCL console (automatisé) :
```tcl
# Si Platform Designer pas encore généré :
qsys-generate soc_system.qsys --synthesis=VHDL --output-directory=soc_system
# Compilation complète :
execute_flow -compile
```

### Temps estimé : **15-25 minutes** sur un PC moderne (le HPS prend du temps).

---

## 🔧 Étape 7 : Générer le .rbf pour la SD card

Après compilation, le fichier `.sof` est dans `output_files/spmv_top.sof`.

Pour le convertir en `.rbf` (Raw Binary File) pour la SD card :

```
File → Convert Programming Files
  → Output: Raw Binary File (.rbf)
  → Mode: Passive Parallel x16 (pour config depuis HPS)
  → Input: output_files/spmv_top.sof
  → Output: output_files/spmv_top.rbf
```

Ou en ligne de commande :
```bash
quartus_cpf -c output_files/spmv_top.sof output_files/spmv_top.rbf
```

---

## 📋 Résumé : Checklist avant compilation

- [ ] Platform Designer : système `soc_system` créé avec HPS + SpMV IP
- [ ] Platform Designer : Generate HDL exécuté → dossier `soc_system/` créé
- [ ] Quartus : Top-level entity = `spmv_top`
- [ ] Quartus : Device = `5CSEBA6U23I7`
- [ ] Fichiers ajoutés :
  - [ ] `soc_system/synthesis/soc_system.qip`
  - [ ] `hdl/spmv_top.vhd`  
  - [ ] `quartus/spmv_timing.sdc`
- [ ] Pin assignments : Clocks, LEDs, Keys, Switches
- [ ] Compilation réussie → `output_files/spmv_top.sof`
- [ ] Conversion `.sof` → `.rbf`

---

## ⚠️ Erreurs courantes

| Erreur | Cause | Solution |
|--------|-------|----------|
| `Error: can't find design unit "work.spmv_pkg"` | Package pas compilé avant l'IP | Vérifier que `spmv_pkg.vhd` est dans le .qip OU ajouté manuellement avant `spmv_accelerator.vhd` |
| `Error: Top-level entity "spmv_top" is undefined` | Mauvais top-level ou fichier pas ajouté | Settings → Top-level entity = `spmv_top` |
| `Error: missing port "xxx" in soc_system` | Ports du top-level ne matchent pas le Qsys | Après Generate HDL, vérifier le fichier `soc_system.vhd` et adapter `spmv_top.vhd` si les noms diffèrent |
| `Warning: No clocks defined in SDC` | SDC pas ajouté au projet | Project → Add/Remove Files → ajouter `spmv_timing.sdc` |
| `Info: soc_system.qip not found` | Platform Designer pas encore généré | Tools → Platform Designer → Generate HDL d'abord |

---

## 🔑 Point critique : Adapter `spmv_top.vhd` à VOTRE Qsys
Le fichier `spmv_top.vhd` fourni utilise les noms de ports **standards** du template DE10-Nano (Terasic Golden Hardware Reference Design). 

**Après avoir généré votre système Qsys**, vérifiez que les noms de ports correspondent :

1. Ouvrez `soc_system/synthesis/soc_system.vhd` (auto-généré)
2. Regardez la déclaration `entity soc_system is port (...)`
3. Comparez avec le `component soc_system` dans `spmv_top.vhd`
4. Adaptez si nécessaire (les noms dépendent de vos choix dans Platform Designer)

**Astuce** : Si vous partez du **DE10-Nano GHRD** (Golden Hardware Reference Design) de Terasic, les noms seront déjà compatibles.
