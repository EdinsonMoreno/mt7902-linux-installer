#!/usr/bin/env bash
# Minimal dry-run test: verifica que el script no tenga errores de sintaxis
# y que las rutas y binarios requeridos existan.

FAIL=0

echo "=== Test: Syntax check ==="
bash -n install.sh || { echo "FAIL: syntax error in install.sh"; FAIL=1; }
bash -n uninstall.sh || { echo "FAIL: syntax error in uninstall.sh"; FAIL=1; }

echo ""
echo "=== Test: Required binaries ==="
for cmd in git gcc make modprobe depmod lspci lsusb; do
  if command -v $cmd &>/dev/null; then
    echo "  [ok] $cmd"
  else
    echo "  [warn] $cmd not found (may be needed)"
  fi
done

echo ""
echo "=== Test: Kernel headers ==="
KVER=$(uname -r)
if [ -d "/lib/modules/$KVER/build" ]; then
  echo "  [ok] kernel headers for $KVER"
else
  echo "  [warn] kernel headers not found for $KVER"
fi

echo ""
echo "=== Test: WiFi hardware ==="
if lspci -d 14c3:7902 2>/dev/null | grep -q .; then
  echo "  [ok] MT7902 WiFi detectado: $(lspci -d 14c3:7902)"
else
  echo "  [warn] MT7902 WiFi (14c3:7902) no detectado"
fi

echo ""
echo "=== Test: WiFi driver instalado ==="
if find /lib/modules/$(uname -r) -name "mt7902e.ko*" 2>/dev/null | grep -q .; then
  echo "  [ok] mt7902e instalado"
else
  echo "  [warn] mt7902e no instalado (instalar con: sudo bash install.sh)"
fi

echo ""
echo "=== Test: Bluetooth hardware ==="
if lsusb 2>/dev/null | grep -qi "13d3"; then
  echo "  [ok] USB Bluetooth MT7902 detectado"
else
  echo "  [info] USB Bluetooth MT7902 no detectado (puede no estar presente)"
fi

echo ""
echo "=== Test: Bluetooth driver instalado ==="
if find /lib/modules/$(uname -r) -name "btusb_mt7902.ko*" 2>/dev/null | grep -q .; then
  echo "  [ok] btusb_mt7902 instalado"
else
  echo "  [warn] btusb_mt7902 no instalado (instalar con: sudo bash install.sh)"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests failed."
  exit 1
fi
