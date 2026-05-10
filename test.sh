#!/usr/bin/env bash
# Minimal dry-run test: verifica que el script no tenga errores de sintaxis
# y que las rutas y binarios requeridos existan.

FAIL=0

echo "=== Test: Syntax check ==="
bash -n install.sh || { echo "FAIL: syntax error in install.sh"; FAIL=1; }
bash -n uninstall.sh || { echo "FAIL: syntax error in uninstall.sh"; FAIL=1; }

echo ""
echo "=== Test: Required binaries ==="
for cmd in git gcc make modprobe depmod lspci; do
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
if [ "$FAIL" -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests failed."
  exit 1
fi
