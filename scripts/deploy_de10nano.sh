#!/bin/bash
# =============================================================================
# deploy_de10nano.sh — Déploiement automatisé via SSH
# Usage : ./deploy_de10nano.sh <IP_DE10_NANO>
# =============================================================================

set -euo pipefail

DE10_IP="${1:?Usage: $0 <IP_DE10_NANO>}"
DE10_USER="root"
RBF_FILE="output_files/soc_system.rbf"
DRIVER_BIN="sw/spmv_driver_arm"

echo "========================================"
echo "  Déploiement SpMV sur DE10-Nano"
echo "  Cible : ${DE10_USER}@${DE10_IP}"
echo "========================================"

echo "[1/5] Vérification des fichiers..."
[ -f "$RBF_FILE" ]  || { echo "ERREUR: $RBF_FILE manquant"; exit 1; }
[ -f "$DRIVER_BIN" ] || { echo "ERREUR: $DRIVER_BIN manquant"; exit 1; }

echo "[2/5] Copie des fichiers..."
scp "$RBF_FILE"  "${DE10_USER}@${DE10_IP}:/root/spmv.rbf"
scp "$DRIVER_BIN" "${DE10_USER}@${DE10_IP}:/root/spmv_driver"

echo "[3/5] Configuration du FPGA..."
ssh "${DE10_USER}@${DE10_IP}" << 'REMOTE'
set -e
echo 0 > /sys/class/fpga-bridge/fpga2hps/enable 2>/dev/null || true
echo 0 > /sys/class/fpga-bridge/hps2fpga/enable 2>/dev/null || true
echo 0 > /sys/class/fpga-bridge/lwhps2fpga/enable 2>/dev/null || true
mkdir -p /lib/firmware
cp /root/spmv.rbf /lib/firmware/spmv.rbf
echo spmv.rbf > /sys/class/fpga_manager/fpga0/firmware
echo 1 > /sys/class/fpga-bridge/fpga2hps/enable 2>/dev/null || true
echo 1 > /sys/class/fpga-bridge/hps2fpga/enable 2>/dev/null || true
echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable 2>/dev/null || true
echo "[OK] FPGA configuré et bridges activés"
REMOTE

echo "[4/5] Vérification mémoire..."
ssh "${DE10_USER}@${DE10_IP}" << 'REMOTE'
[ -c /dev/mem ] && echo "[OK] /dev/mem accessible" || echo "[WARN] /dev/mem manquant"
REMOTE

echo "[5/5] Exécution..."
ssh "${DE10_USER}@${DE10_IP}" << 'REMOTE'
chmod +x /root/spmv_driver
echo "=== Test 3×3 ==="
/root/spmv_driver
echo ""
echo "=== Test Cora ==="
/root/spmv_driver --cora
REMOTE

echo "========================================"
echo "  Déploiement terminé !"
echo "========================================"
