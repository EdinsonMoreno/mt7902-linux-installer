<div align="center">
  <h1>MT7902 Linux Installer</h1>
  <p>
    <strong>Instalador automatizado para el chip WiFi + Bluetooth MediaTek MT7902 (Filogic 310)</strong>
  </p>
  <p>
    <img src="https://img.shields.io/badge/kernel-6.6~7.0-blue" alt="Kernel support">
    <img src="https://img.shields.io/badge/license-GPLv2-green" alt="License">
  </p>
</div>

## Problemática

El **MediaTek MT7902** (PCI ID `14c3:7902`) es un chip WiFi 6E usado en muchos laptops modernos (ASUS Vivobook, etc.) que **no tiene soporte estable en Linux mainline** hasta kernel 7.1.

MediaTek envió los parches oficiales al mailing list de Linux en Febrero 2026 (serie de 11 patches), pero fueron aceptados para **kernel 7.1+**. Mientras tanto, este instalador usa un backport comunitario mantenido por [hmtheboy154](https://github.com/hmtheboy154/mt7902) que adapta esos mismos parches para kernels 6.6+.

### Hardware afectado

Dispositivos que usan este chip:
- AzureWave AW-XB552NF (PCI subsys `1a3b:5520`)
- Cualquier módulo M.2 con chip MT7902 (PCI `14c3:7902`)

## Qué hace este instalador

1. Detecta tu distribución y kernel
2. Verifica presencia del hardware MT7902 (PCI `14c3:7902`)
3. Instala dependencias de compilación
4. Descarga el driver del repositorio del fabricante
5. Compila el módulo `mt7902e.ko`
6. Blackliste los módulos `mt76` in-tree que causan conflicto de símbolos
7. Configura carga automática del módulo al boot
8. Reconstruye el initramfs
9. Registra el módulo en **DKMS** para que sobreviva actualizaciones de kernel
10. Instala el driver Bluetooth `btusb_mt7902` desde el branch `bluetooth_backport`
11. Carga el driver y verifica que el hardware sea detectado

## Requisitos

- **Conexión a internet por cable** (WiFi no anda hasta instalar el driver)
- **Secure Boot deshabilitado** (o firmar el módulo manualmente)
- **Kernel 6.6+**
- **Arquitectura**: x86_64

### Soporte por distribución

| Distribución | Estado |
|-------------|--------|
| Fedora 40/41/42/43/44 | ✅ Probado |
| RHEL 9 / Rocky / Alma | ✅ Debería funcionar |
| Ubuntu 24.04+ | ✅ Debería funcionar |
| Arch Linux | ✅ Debería funcionar |
| CachyOS / Garuda / Artix / ArcoLinux | ✅ Soportado |
| Debian 12+ | ✅ Debería funcionar |

## Instalación

```bash
git clone https://github.com/EdinsonMoreno/mt7902-linux-installer.git
cd mt7902-linux-installer
sudo bash install.sh
```

Esperá ~2 minutos mientras se compila e instala todo automáticamente.

### Opciones

```bash
sudo bash install.sh --help             # Ver ayuda
sudo bash install.sh --no-dkms           # No registrar en DKMS
sudo bash install.sh --no-fw             # No instalar firmware
sudo bash install.sh --no-initramfs      # No reconstruir initramfs
sudo bash install.sh --no-bt             # No instalar driver Bluetooth
```

## Después de la instalación

El WiFi debería funcionar inmediatamente. Conectate con:

```bash
nmcli device wifi list                              # Listar redes
nmcli device wifi connect "MI_RED" password "CLAVE"  # Conectarse
```

**Configurá la red como autoconnect** (NetworkManager lo hace por defecto cuando te conectás).

Cuando estés listo, reiniciá y verificá que el WiFi se conecta automáticamente.

## Soporte Bluetooth

El instalador también configura el driver Bluetooth del MT7902 automáticamente.

**¿Por qué es necesario?**
El driver `btmtk` del kernel no incluye soporte para el MT7902. El chip MT7902 requiere
la función `btmtk_setup_firmware_79xx()` y tiene un USB ID (`13d3:3579`) que no está en
la tabla de dispositivos del driver in-tree. Sin este fix, el resultado es un
HCI Reset timeout (-110) y el controller Bluetooth nunca aparece disponible.

Este instalador compila el módulo parcheado `btusb_mt7902` desde el branch
`bluetooth_backport` del mismo repositorio del driver WiFi.

**Características Bluetooth habilitadas:**
- Bluetooth 5.x (2M PHY, Coded PHY)
- A2DP (audio inalámbrico)
- HFP (manos libres)
- BLE (Bluetooth Low Energy)

Para omitir la instalación de Bluetooth:
```bash
sudo bash install.sh --no-bt
```

**Firmware BT requerido** (incluido en `linux-firmware >= 20260410`):
`/lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin.xz`

El instalador intenta instalar `linux-firmware` automáticamente si el firmware no está presente.

## ¿Cómo funciona a nivel técnico?

El chip MT7902 usa una arquitectura interna muy distinta a modelos anteriores (MT7921, MT7925). A diferencia de otros chips de MediaTek que comparten el mismo firmware y secuencia de inicialización, el MT7902 requiere:

- Un layout de DMA diferente en el core `mt76_connac3`
- Una secuencia específica de arranque del MCU con verificación de semáforo
- Firmware dedicado (`WIFI_MT7902_patch_mcu_1_1_hdr.bin` + `WIFI_RAM_CODE_MT7902_1.bin`)

El módulo `mt7902e.ko` empaqueta internamente todo el stack `mt76` + `mt76-connac-lib` + `mt792x-lib` + el driver específico. Esto es necesario porque los cambios son muy profundos y no es viable parchear cada sub-módulo individualmente. Por eso hay que blacklistear los módulos in-tree.

Para Bluetooth, el driver in-tree `btusb` se engancha al chip por alias genérico de clase (0xE0) pero sin el flag `BTUSB_MEDIATEK`, por lo que nunca llama a `btmtk_setup_firmware_79xx()`. El módulo `btusb_mt7902` soluciona esto y blacklistea los drivers in-tree `btusb` y `btmtk`.

## Limitaciones conocidas del driver

| Característica | Teórico MT7902 | Con este driver |
|---|---|---|
| MIMO | 2x2 | 1x1 (limitación del módulo out-of-tree) |
| Ancho de canal | 160 MHz | 80 MHz máximo |
| Estándar | WiFi 6E | WiFi 6E (6GHz disponible) |
| Bluetooth | 5.x | 5.x ✅ (con este instalador) |

El soporte mainline completo (incluyendo 2x2 MIMO y 160MHz) está proyectado para kernel 7.1+.
Cuando estés en kernel 7.1+, podés desinstalar este driver y usar el soporte nativo.

## Desinstalación

```bash
sudo bash uninstall.sh
```

Esto elimina tanto el driver WiFi como el driver Bluetooth y sus respectivos blacklists.

## Créditos

- **[hmtheboy154](https://github.com/hmtheboy154/mt7902)** — Driver backport basado en los parches oficiales de MediaTek (WiFi + Bluetooth)
- **[sean.wang@mediatek.com](mailto:sean.wang@mediatek.com)** — Parches oficiales enviados a linux-wireless (Feb 2026)
- **[checkitsnow](https://github.com/checkitsnow/MT7902_linux_drv)** — Guía de instalación y documentación
- **Comunidad** — Testing y reportes en múltiples dispositivos

## Links útiles

- [Parches oficiales en lore.kernel.org](https://lore.kernel.org/all/20260219004007.19733-1-sean.wang@kernel.org/)
- [Driver original (backport para 6.6+)](https://github.com/hmtheboy154/mt7902)
- [Driver gen4 (Xiaomi BSP) - descontinuado](https://github.com/hmtheboy154/gen4-mt7902)
- [Guía alternativa (checkitsnow)](https://github.com/checkitsnow/MT7902_linux_drv)
- [Artículo CNX Software](https://www.cnx-software.com/2026/02/20/mediatek-mt7902-wireless-chipset-finally-gets-linux-drivers/)
