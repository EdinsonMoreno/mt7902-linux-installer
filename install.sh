#!/usr/bin/env bash
set -euo pipefail

# mt7902-linux-installer
# Automated installer for MediaTek MT7902 WiFi + Bluetooth driver on Linux (kernel 6.6+)
# Driver source: https://github.com/EdinsonMoreno/mt7902-fork (backport branch)
# Official patches (Linux 7.1+): https://lore.kernel.org/all/20260219004007.19733-1-sean.wang@kernel.org/

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

ARCH="$(uname -m)"
KVER="$(uname -r)"
# CN-008: validate KVER format before using it in package install commands
[[ "$KVER" =~ ^[0-9]+\.[0-9]+\.[0-9a-zA-Z._-]+$ ]] || { echo -e "\033[0;31m[✗]\033[0m KVER inválido: $KVER"; exit 1; }
# CN-024: validate architecture is x86_64 before proceeding
[ "$ARCH" = "x86_64" ] || { echo -e "\033[0;31m[✗]\033[0m Arquitectura no soportada: $ARCH. Solo x86_64."; exit 1; }
DISTRO=""
DRIVER_REPO="https://github.com/EdinsonMoreno/mt7902-fork.git"
DRIVER_BRANCH="backport"
# CN-002: use mktemp for unpredictable temp dirs — prevents TOCTOU/symlink attacks as root
DRIVER_DIR=$(mktemp -d -t mt7902-src.XXXXXX)
MODNAME="mt7902e"
BLACKLIST_FILE="/etc/modprobe.d/mt7902-blacklist.conf"
LOAD_FILE="/etc/modules-load.d/mt7902e.conf"

# Bluetooth variables
BT_DRIVER_REPO="https://github.com/hmtheboy154/mt7902"
BT_BRANCH="bluetooth_backport"
BT_MODNAME="btusb_mt7902"
# CN-002: use mktemp for unpredictable temp dirs — prevents TOCTOU/symlink attacks as root
BT_DIR=$(mktemp -d -t mt7902-bt.XXXXXX)
trap 'rm -rf "$DRIVER_DIR" "$BT_DIR"' EXIT
BLACKLIST_BT_FILE="/etc/modprobe.d/mt7902-bt-blacklist.conf"
INSTALL_BT=1  # default: instalar BT

detect_distro() {
  if [ -f /etc/os-release ]; then
    # CN-003: parse without dot-source to avoid executing arbitrary code as root
    DISTRO=$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"')
    VERSION_ID=$(grep -E '^VERSION_ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"' || true)
  elif command -v lsb_release &>/dev/null; then
    DISTRO="$(lsb_release -is)"
  else
    err "No se pudo detectar la distribución"
  fi
  log "Distro detectada: $DISTRO ${VERSION_ID:-}"
}

check_kernel() {
  local major minor
  IFS='.' read -r major minor _ <<< "$KVER"
  if [ "$major" -lt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -lt 6 ]; }; then
    err "Kernel $KVER demasiado antiguo. Se requiere 6.6+."
  fi
  if [ "$major" -ge 7 ] && [ "$minor" -ge 1 ]; then
    warn "Kernel $KVER: el soporte mainline del MT7902 puede estar disponible. Probá sin este instalador primero."
  else
    log "Kernel $KVER compatible"
  fi
  log "Kernel: $KVER ($ARCH)"
}

check_hardware() {
  if ! lspci -d 14c3:7902 &>/dev/null || [ -z "$(lspci -d 14c3:7902)" ]; then
    err "No se detectó el chip MT7902 (PCI ID 14c3:7902). Este instalador es solo para ese hardware."
  fi
  log "Hardware MT7902 detectado: $(lspci -d 14c3:7902)"
}

check_secureboot() {
  if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
    warn "Secure Boot ACTIVADO — el módulo sin firma podría ser rechazado."
    warn "Deshabilitalo desde la BIOS/UEFI o firmá el módulo con mokutil."
    warn "Continuando de todas formas..."
  fi
}

install_deps_fedora() {
  # CN-027: drop | tail -1 so pipefail catches errors
  dnf install -y git gcc make kernel-devel-"$KVER" patch 2>/dev/null \
    || err "Falló dnf install de dependencias"
}
install_deps_rhel() {
  # CN-027: drop | tail -1 so pipefail catches errors
  dnf install -y git gcc make kernel-devel-"$KVER" patch 2>/dev/null \
    || err "Falló dnf install de dependencias"
}
install_deps_ubuntu() {
  # CN-027: drop | tail -1 so pipefail catches errors
  apt-get update -qq && apt-get install -y git gcc make linux-headers-"$KVER" patch 2>/dev/null \
    || err "Falló apt-get install de dependencias"
}
install_deps_arch() {
  # CN-027: drop | tail -1 so pipefail catches errors
  pacman -Sy --noconfirm git gcc make linux-headers patch 2>/dev/null \
    || err "Falló pacman install de dependencias"
}

install_deps() {
  info "Instalando dependencias de compilación..."
  case "$DISTRO" in
    fedora) install_deps_fedora ;;
    rhel|centos|rocky|alma) install_deps_rhel ;;
    ubuntu|debian|pop|mint) install_deps_ubuntu ;;
    arch|manjaro|endeavouros|cachyos|garuda|artix|arcolinux) install_deps_arch ;;
    *) err "Distro no soportada: $DISTRO. Instalá gcc, make y kernel-devel manualmente." ;;
  esac
  log "Dependencias instaladas"
}

download_driver() {
  info "Descargando driver MT7902..."
  rm -rf "$DRIVER_DIR"
  # CN-027: drop | tail -1 so pipefail catches errors; CN-001(partial): print commit SHA
  git clone --depth=1 --branch "$DRIVER_BRANCH" "$DRIVER_REPO" "$DRIVER_DIR" 2>/dev/null \
    || { err "Falló git clone de $DRIVER_REPO (rama $DRIVER_BRANCH)"; }
  DRIVER_COMMIT=$(git -C "$DRIVER_DIR" rev-parse HEAD)
  warn "Commit del driver clonado: $DRIVER_COMMIT"
  warn "Verificá en https://github.com/EdinsonMoreno/mt7902-fork/commit/$DRIVER_COMMIT que este commit es de confianza."
  log "Driver descargado"
}

compile_driver() {
  info "Compilando driver (esto puede tomar minutos)..."
  # CN-009: subshell preserves CWD; CN-027: drop | tail -1 so pipefail works
  ( cd "$DRIVER_DIR" && make -j"$(nproc)" ) || err "Falló la compilación del driver. Ejecutá 'make' manualmente en $DRIVER_DIR para ver el error."
  if [ ! -f "$DRIVER_DIR/mt7902e.ko" ]; then
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
  # CN-027: drop | tail -1 so pipefail catches errors
  if command -v dracut &>/dev/null; then
    dracut -f --add-drivers "$MODNAME" \
      --include "$BLACKLIST_FILE" "$BLACKLIST_FILE" \
      --include "$LOAD_FILE" "$LOAD_FILE" \
      /boot/initramfs-"$KVER".img "$KVER" 2>/dev/null \
      || err "Falló dracut al reconstruir initramfs"
  elif command -v update-initramfs &>/dev/null; then
    update-initramfs -u -k "$KVER" 2>/dev/null \
      || err "Falló update-initramfs"
  elif command -v mkinitcpio &>/dev/null; then
    mkinitcpio -g /boot/initramfs-"$KVER".img 2>/dev/null \
      || err "Falló mkinitcpio"
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
MAKE="make -j\$(nproc) KVER=\$kernelver"
CLEAN="make clean KVER=\$kernelver"
BUILT_MODULE_LOCATION="."
EOF
  # CN-027: drop | tail -1 so pipefail catches errors in dkms operations
  dkms add -m "$MODNAME" -v 1.0 2>/dev/null \
    || err "Falló dkms add"
  dkms build -m "$MODNAME" -v 1.0 2>/dev/null \
    || err "Falló dkms build. Revisá los logs en /var/lib/dkms/$MODNAME/1.0/build/"
  dkms install -m "$MODNAME" -v 1.0 2>/dev/null \
    || err "Falló dkms install"
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
  local pci_slot
  pci_slot=$(lspci -d 14c3:7902 | awk '{print $1}' | head -1)
  if [ -z "$pci_slot" ]; then
    warn "No se detectó hardware MT7902 (14c3:7902)"
  else
    if ! lspci -k -s "$pci_slot" 2>/dev/null | grep -q "Kernel driver in use: $MODNAME"; then
      warn "Driver no asociado al dispositivo PCI $pci_slot"
      lspci -k -s "$pci_slot" 2>/dev/null | grep -E "Network|driver" || true
    else
      log "Driver asociado al hardware"
    fi
  fi
  if iw dev 2>/dev/null | grep -q "Interface"; then
    local iface
    iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2}')
    log "Interfaz inalámbrica detectada: $iface"
  else
    warn "No se detectó interfaz inalámbrica — revisá dmesg"
  fi
}

install_bluetooth() {
  if [ "$INSTALL_BT" -eq 0 ]; then
    info "Saltando instalación de Bluetooth (--no-bt)"
    return
  fi

  info "=== Instalando driver Bluetooth MT7902 ==="

  # Verificar que el chip BT esté presente
  # CN-007: safe while-read loop instead of xargs -I{} sh -c to prevent path injection
  local BT_FOUND=0
  if lsusb 2>/dev/null | grep -qi "13d3:3579\|13d3:3580"; then
    BT_FOUND=1
  else
    while IFS= read -r -d '' vendorfile; do
      dir=$(dirname "$vendorfile")
      grep -q "3579\|3580" "$dir/idProduct" 2>/dev/null && { BT_FOUND=1; break; }
    done < <(find /sys/bus/usb/devices -name "idVendor" -print0 2>/dev/null)
  fi
  if [ "$BT_FOUND" -eq 0 ]; then
    warn "No se detectó interfaz USB Bluetooth MT7902 (13d3:3579). Saltando BT."
    return
  fi

  # Verificar firmware
  if [ ! -f "/lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin.xz" ] && \
     [ ! -f "/lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin" ]; then
    warn "Firmware BT no encontrado. Intentando instalar linux-firmware..."
    case "$DISTRO" in
      fedora|rhel|centos|rocky|alma) dnf install -y linux-firmware ;;
      ubuntu|debian|pop|mint) apt-get install -y linux-firmware ;;
      arch|manjaro|endeavouros|cachyos|garuda|artix|arcolinux) pacman -Sy --noconfirm linux-firmware ;;
    esac
  fi

  # Clonar branch bluetooth_backport
  # CN-002: BT_DIR already created by mktemp; clear it before use
  rm -rf "${BT_DIR:?}"/*
  # CN-027: git clone without | tail -1 so pipefail catches errors
  git clone --depth=1 --branch "$BT_BRANCH" "$BT_DRIVER_REPO" "$BT_DIR" 2>/dev/null || {
    warn "No se pudo clonar bluetooth_backport. Intentando fetch directo..."
    # CN-009: subshell preserves CWD for the git init fallback
    ( cd "$BT_DIR" && git init \
      && git fetch "$BT_DRIVER_REPO" "refs/remotes/origin/$BT_BRANCH:$BT_BRANCH" --depth=1 \
      && git checkout "$BT_BRANCH" ) || {
      warn "No se pudo obtener el branch BT. Saltando instalación de Bluetooth."
      return
    }
  }
  # CN-001(partial): print BT commit SHA for manual verification
  BT_COMMIT=$(git -C "$BT_DIR" rev-parse HEAD 2>/dev/null || true)
  [ -n "$BT_COMMIT" ] && {
    warn "Commit del driver BT clonado: $BT_COMMIT"
    warn "Verificá en https://github.com/hmtheboy154/mt7902/commit/$BT_COMMIT que este commit es de confianza."
  }

  # Compilar — CN-009: subshell preserves CWD; CN-027: drop | tail -1 so pipefail works
  ( cd "$BT_DIR" && make -j"$(nproc)" KVER="$KVER" ) || {
    warn "Fallo al compilar driver BT. Saltando instalación de Bluetooth."
    return
  }

  # Buscar el .ko generado
  local bt_ko
  bt_ko=$(find "$BT_DIR" -name "${BT_MODNAME}.ko" | head -1)
  if [ -z "$bt_ko" ]; then
    warn "No se generó ${BT_MODNAME}.ko. Saltando instalación de Bluetooth."
    return
  fi

  # Instalar
  local bt_destdir="/lib/modules/$KVER/kernel/drivers/bluetooth/${BT_MODNAME}"
  mkdir -p "$bt_destdir"
  install -m 644 "$bt_ko" "$bt_destdir/"

  # Comprimir si el sistema usa .ko.xz
  if find /lib/modules/"$KVER"/kernel -name "*.ko.xz" | head -1 | grep -q "."; then
    xz -f "$bt_destdir/${BT_MODNAME}.ko" 2>/dev/null || true
  fi

  depmod -a
  log "Módulo BT instalado: ${bt_destdir}"

  # Blacklist in-tree btusb y btmtk
  cat > "$BLACKLIST_BT_FILE" << 'EOF'
# Blacklist in-tree btusb/btmtk — usar versión parcheada btusb_mt7902 para MT7902 (13d3:3579)
# Generado por mt7902-linux-installer
blacklist btusb
blacklist btmtk
EOF
  log "Blacklist BT creado: $BLACKLIST_BT_FILE"

  # Descargar módulos viejos y cargar nuevo
  modprobe -r btusb btmtk 2>/dev/null || true
  sleep 1
  depmod -a
  modprobe "$BT_MODNAME" 2>/dev/null && {
    sleep 3
    systemctl restart bluetooth 2>/dev/null || true
    sleep 2
    if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
      log "Bluetooth MT7902 inicializado correctamente"
      bluetoothctl show 2>/dev/null | grep -E "Controller|Powered|Name" | head -5 || true
    else
      warn "Bluetooth instalado pero controller no visible aún — reiniciá para activarlo completamente"
    fi
  } || warn "Módulo BT cargado pero requiere reinicio"

  log "=== Bluetooth instalado ==="
}

cleanup() {
  # CN-002: DRIVER_DIR and BT_DIR are cleaned up by the trap registered at startup
  log "Archivos temporales serán eliminados al salir (trap EXIT)"
}

usage() {
  cat << EOF
Uso: sudo bash install.sh [opciones]

Opciones:
  --help, -h     Muestra esta ayuda
  --no-dkms      No registra en DKMS
  --no-fw        No instala firmware (usá el de tu distro)
  --no-initramfs No reconstruye initramfs
  --no-bt        No instala el driver Bluetooth

El instalador:
  1. Detecta distro y kernel
  2. Verifica presencia del hardware MT7902
  3. Instala dependencias de compilación
  4. Descarga y compila el driver mt7902e
  5. Blackliste módulos conflictivos del kernel in-tree
  6. Configura carga automática del módulo
  7. Reconstruye initramfs
  8. Registra en DKMS para persistencia en updates
  9. Instala driver Bluetooth (btusb_mt7902) desde bluetooth_backport
  10. Carga el driver y verifica

Soporte: Fedora, RHEL, Ubuntu/Debian, Arch Linux
Kernel: 6.6+
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
      --no-bt) INSTALL_BT=0; shift ;;
      *) err "Opción desconocida: $1";;
    esac
  done

  echo -e "${CYAN}============================================${NC}"
  echo -e "${CYAN}  MediaTek MT7902 Linux Driver Installer${NC}"
  echo -e "${CYAN}  Driver: EdinsonMoreno/mt7902-fork (backport)${NC}"
  echo -e "${CYAN}  Kernel target: 6.6+${NC}"
  echo -e "${CYAN}============================================${NC}"
  echo ""

  detect_distro
  check_hardware
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
  install_bluetooth
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
