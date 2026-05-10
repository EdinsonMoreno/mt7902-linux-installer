#!/usr/bin/env bash
set -euo pipefail

# mt7902-linux-installer
# Automated installer for MediaTek MT7902 WiFi driver on Linux (kernel 6.6~6.19)
# Driver source: https://github.com/hmtheboy154/mt7902
# Official patches (Linux 7.1+): https://lore.kernel.org/all/20260219004007.19733-1-sean.wang@kernel.org/

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

ARCH="$(uname -m)"
KVER="$(uname -r)"
DISTRO=""
DRIVER_REPO="https://github.com/hmtheboy154/mt7902.git"
DRIVER_DIR="/tmp/mt7902-src"
MODNAME="mt7902e"
BLACKLIST_FILE="/etc/modprobe.d/mt7902-blacklist.conf"
LOAD_FILE="/etc/modules-load.d/mt7902e.conf"

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="$ID"
  elif command -v lsb_release &>/dev/null; then
    DISTRO="$(lsb_release -is)"
  else
    err "No se pudo detectar la distribución"
  fi
  log "Distro detectada: $DISTRO $VERSION_ID"
}

check_kernel() {
  local major minor
  IFS='.' read -r major minor _ <<< "$KVER"
  if [ "$major" -lt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -gt 19 ]; }; then
    warn "Kernel $KVER puede no ser compatible (soporte oficial: 6.6~6.19)"
    warn "Si es kernel 7.0+, el driver ya está en mainline. Probá sin este instalador."
  fi
  log "Kernel: $KVER ($ARCH)"
}

check_secureboot() {
  if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
    warn "Secure Boot ACTIVADO — el módulo sin firma podría ser rechazado."
    warn "Deshabilitalo desde la BIOS/UEFI o firmá el módulo con mokutil."
    warn "Continuando de todas formas..."
  fi
}

install_deps_fedora() {
  dnf install -y git gcc make kernel-devel-"$KVER" patch 2>&1 | tail -1
}
install_deps_rhel() {
  dnf install -y git gcc make kernel-devel-"$KVER" patch 2>&1 | tail -1
}
install_deps_ubuntu() {
  apt-get update -qq && apt-get install -y git gcc make linux-headers-"$KVER" patch 2>&1 | tail -1
}
install_deps_arch() {
  pacman -Sy --noconfirm git gcc make linux-headers patch 2>&1 | tail -1
}

install_deps() {
  info "Instalando dependencias de compilación..."
  case "$DISTRO" in
    fedora) install_deps_fedora ;;
    rhel|centos|rocky|alma) install_deps_rhel ;;
    ubuntu|debian|pop|mint) install_deps_ubuntu ;;
    arch|manjaro|endeavouros) install_deps_arch ;;
    *) err "Distro no soportada: $DISTRO. Instalá gcc, make y kernel-devel manualmente." ;;
  esac
  log "Dependencias instaladas"
}

download_driver() {
  info "Descargando driver MT7902..."
  rm -rf "$DRIVER_DIR"
  git clone --depth=1 "$DRIVER_REPO" "$DRIVER_DIR" 2>&1 | tail -1
  log "Driver descargado"
}

compile_driver() {
  info "Compilando driver (esto puede tomar minutos)..."
  cd "$DRIVER_DIR"
  make -j"$(nproc)" 2>&1 | tail -1
  if [ ! -f mt7902e.ko ]; then
    err "Compilación falló — revisá los errores arriba"
  fi
  log "Compilación exitosa"
}

install_module() {
  info "Instalando módulo..."
  local destdir="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/$MODNAME"
  mkdir -p "$destdir"
  cp "$DRIVER_DIR/mt7902e.ko" "$destdir/"
  depmod -a
  log "Módulo instalado en $destdir"
}

install_firmware() {
  info "Instalando firmware..."
  local fwdir="/lib/firmware/mediatek"
  mkdir -p "$fwdir"
  cp "$DRIVER_DIR"/firmware/*.bin "$fwdir/" 2>/dev/null || true
  log "Firmware instalado"
}

blacklist_modules() {
  info "Blacklisteando módulos conflictivos..."
  cat > "$BLACKLIST_FILE" << 'EOF'
# Blacklist in-tree Mediatek mt76 modules — conflictúan con mt7902e out-of-tree
blacklist mt76
blacklist mt76_connac_lib
blacklist mt792x_lib
blacklist mt7921_common
blacklist mt7921e
blacklist mt7925_common
blacklist mt7925e
EOF
  log "Blacklist creada: $BLACKLIST_FILE"
}

setup_autoload() {
  info "Configurando carga automática..."
  echo "$MODNAME" > "$LOAD_FILE"
  log "Auto-load configurado: $LOAD_FILE"
}

rebuild_initramfs() {
  info "Reconstruyendo initramfs..."
  if command -v dracut &>/dev/null; then
    dracut -f --add-drivers "$MODNAME" \
      --include "$BLACKLIST_FILE" "$BLACKLIST_FILE" \
      --include "$LOAD_FILE" "$LOAD_FILE" \
      /boot/initramfs-"$KVER".img "$KVER" 2>&1 | tail -1
  elif command -v update-initramfs &>/dev/null; then
    update-initramfs -u -k "$KVER" 2>&1 | tail -1
  elif command -v mkinitcpio &>/dev/null; then
    mkinitcpio -g /boot/initramfs-"$KVER".img 2>&1 | tail -1
  else
    warn "No se pudo reconstruir initramfs automáticamente. Hacelo manual."
  fi
  log "Initramfs reconstruido"
}

install_dkms() {
  info "Registrando módulo en DKMS..."
  if ! command -v dkms &>/dev/null; then
    warn "DKMS no instalado. Instalalo manualmente para que el módulo sobreviva updates de kernel."
    return
  fi
  local src="/usr/src/$MODNAME-1.0"
  rm -rf "$src"
  cp -r "$DRIVER_DIR" "$src"
  cat > "$src/dkms.conf" << EOF
PACKAGE_NAME="$MODNAME"
PACKAGE_VERSION="1.0"
BUILT_MODULE_NAME="$MODNAME"
DEST_MODULE_LOCATION="/kernel/drivers/net/wireless/mediatek/$MODNAME"
AUTOINSTALL="YES"
MAKE="make -j\$(nproc) -C \$kernel_source_dir M=\$dkms_tree/\$PACKAGE_NAME/\$PACKAGE_VERSION/build/src modules"
CLEAN="make -C \$kernel_source_dir M=\$dkms_tree/\$PACKAGE_NAME/\$PACKAGE_VERSION/build/src clean"
BUILT_MODULE_LOCATION="src"
EOF
  dkms add -m "$MODNAME" -v 1.0 2>&1 | tail -1
  dkms build -m "$MODNAME" -v 1.0 2>&1 | tail -1
  dkms install -m "$MODNAME" -v 1.0 2>&1 | tail -1
  log "DKMS registrado: $MODNAME/1.0"
}

unload_conflicting() {
  info "Descargando módulos in-tree conflictivos..."
  for mod in mt7921e mt7925e mt7921_common mt7925_common mt792x_lib mt76_connac_lib mt76; do
    modprobe -r "$mod" 2>/dev/null || true
  done
  log "Módulos in-tree descargados"
}

load_driver() {
  info "Cargando driver..."
  modprobe "$MODNAME" 2>&1 || err "Fallo al cargar $MODNAME"
  sleep 2
  log "Driver cargado exitosamente"
}

verify_driver() {
  info "Verificando instalación..."
  if ! lsmod | grep -q "$MODNAME"; then
    err "Módulo $MODNAME no cargado"
  fi
  if ! lspci -k -s 02:00.0 2>/dev/null | grep -q "Kernel driver in use: $MODNAME"; then
    warn "Driver no asociado al dispositivo PCI 02:00.0"
    lspci -k -s 02:00.0 2>/dev/null | grep -E "Network|driver" || true
  else
    log "Driver asociado al hardware"
  fi
  if iw dev 2>/dev/null | grep -q "Interface"; then
    local iface
    iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2}')
    log "Interfaz inalámbrica detectada: $iface"
  else
    warn "No se detectó interfaz inalámbrica — revisá dmesg"
  fi
}

cleanup() {
  rm -rf "$DRIVER_DIR"
  log "Archivos temporales eliminados"
}

usage() {
  cat << EOF
Uso: sudo bash install.sh [opciones]

Opciones:
  --help, -h     Muestra esta ayuda
  --no-dkms      No registra en DKMS
  --no-fw        No instala firmware (usá el de tu distro)
  --no-initramfs No reconstruye initramfs

El instalador:
  1. Detecta distro y kernel
  2. Instala dependencias de compilación
  3. Descarga y compila el driver mt7902e
  4. Blackliste módulos conflictivos del kernel in-tree
  5. Configura carga automática del módulo
  6. Reconstruye initramfs
  7. Registra en DKMS para persistencia en updates
  8. Carga el driver y verifica

Soporte: Fedora, RHEL, Ubuntu/Debian, Arch Linux
Kernel: 6.6 ~ 6.19
EOF
  exit 0
}

main() {
  if [ "$EUID" -ne 0 ]; then
    err "Ejecutá como root: sudo bash install.sh"
  fi

  local DKMS=1 FW=1 INITRAMFS=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) usage ;;
      --no-dkms) DKMS=0; shift ;;
      --no-fw) FW=0; shift ;;
      --no-initramfs) INITRAMFS=0; shift ;;
      *) err "Opción desconocida: $1";;
    esac
  done

  echo -e "${CYAN}============================================${NC}"
  echo -e "${CYAN}  MediaTek MT7902 Linux Driver Installer${NC}"
  echo -e "${CYAN}  Driver: hmtheboy154/mt7902 (backport)${NC}"
  echo -e "${CYAN}  Kernel target: 6.6 ~ 6.19${NC}"
  echo -e "${CYAN}============================================${NC}"
  echo ""

  detect_distro
  check_kernel
  check_secureboot
  install_deps
  download_driver
  compile_driver
  install_module
  [ "$FW" -eq 1 ] && install_firmware
  blacklist_modules
  setup_autoload
  unload_conflicting
  load_driver
  [ "$DKMS" -eq 1 ] && install_dkms
  [ "$INITRAMFS" -eq 1 ] && rebuild_initramfs
  verify_driver
  cleanup

  echo ""
  log "Instalación completada exitosamente."
  echo ""
  info "El WiFi debería funcionar AHORA. Probá con:"
  info "  nmcli device wifi list"
  info "  nmcli device wifi connect <SSID> password <PASSWORD>"
  echo ""
  info "Después de reiniciar, el WiFi se conectará automáticamente."
  info "Si actualizás el kernel, DKMS recompilará el módulo solo."
}

main "$@"
