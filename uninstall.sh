#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

KVER="$(uname -r)"
MODNAME="mt7902e"

if [ "$EUID" -ne 0 ]; then
  err "Ejecutá como root: sudo bash uninstall.sh"
fi

echo -e "${CYAN}====================================${NC}"
echo -e "${CYAN}  Desinstalando driver MT7902${NC}"
echo -e "${CYAN}====================================${NC}"
echo ""

# Unload module
if lsmod | grep -q "$MODNAME"; then
  modprobe -r "$MODNAME" 2>/dev/null && log "Módulo descargado" || warn "No se pudo descargar módulo (en uso?)"
fi

# Remove from DKMS
if command -v dkms &>/dev/null && dkms status 2>/dev/null | grep -q "$MODNAME"; then
  dkms remove -m "$MODNAME" -v 1.0 --all 2>/dev/null && log "DKMS: módulo removido"
fi

# Remove source from /usr/src
rm -rf "/usr/src/$MODNAME-1.0" 2>/dev/null || true

# Remove installed module
local modfile="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/$MODNAME/$MODNAME.ko"
rm -f "$modfile"* 2>/dev/null || true
rmdir "/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/$MODNAME" 2>/dev/null || true
log "Módulo eliminado de /lib/modules"

# Remove DKMS extra module
rm -f "/lib/modules/$KVER/extra/$MODNAME.ko"* 2>/dev/null || true

# Remove blacklist
rm -f /etc/modprobe.d/mt7902-blacklist.conf 2>/dev/null && log "Blacklist eliminada" || true

# Remove autoload
rm -f /etc/modules-load.d/mt7902e.conf 2>/dev/null && log "Auto-load eliminado" || true

# Rebuild initramfs
if command -v dracut &>/dev/null; then
  dracut -f /boot/initramfs-"$KVER".img "$KVER" 2>&1 | tail -1
elif command -v update-initramfs &>/dev/null; then
  update-initramfs -u -k "$KVER" 2>&1 | tail -1
fi
log "Initramfs reconstruido"

depmod -a 2>/dev/null || true

echo ""
log "Driver MT7902 desinstalado. Reiniciá para completar la limpieza."
