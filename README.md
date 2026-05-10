<div align="center">
  <h1>MT7902 Linux Installer</h1>
  <p>
    <strong>Instalador automatizado para el chip WiFi MediaTek MT7902 (Filogic 310)</strong>
  </p>
  <p>
    <img src="https://img.shields.io/badge/kernel-6.6~6.19-blue" alt="Kernel support">
    <img src="https://img.shields.io/badge/license-GPLv2-green" alt="License">
  </p>
</div>

## Problemática

El **MediaTek MT7902** (PCI ID `14c3:7902`) es un chip WiFi 6E usado en muchos laptops modernos (ASUS Vivobook, etc.) que **no tiene soporte estable en Linux mainline** hasta kernel 7.1.

MediaTek envió los parches oficiales al mailing list de Linux en Febrero 2026 (serie de 11 patches), pero fueron aceptados para **kernel 7.1+**. Mientras tanto, este instalador usa un backport comunitario mantenido por [hmtheboy154](https://github.com/hmtheboy154/mt7902) que adapta esos mismos parches para kernels 6.6~6.19.

### Hardware afectado

Dispositivos que usan este chip:
- AzureWave AW-XB552NF (PCI subsys `1a3b:5520`)
- Cualquier módulo M.2 con chip MT7902 (PCI `14c3:7902`)

## Qué hace este instalador

1. Detecta tu distribución y kernel
2. Instala dependencias de compilación
3. Descarga el driver del repositorio del fabricante
4. Compila el módulo `mt7902e.ko`
5. Blackliste los módulos `mt76` in-tree que causan conflicto de símbolos
6. Configura carga automática del módulo al boot
7. Reconstruye el initramfs
8. Registra el módulo en **DKMS** para que sobreviva actualizaciones de kernel
9. Carga el driver y verifica que el hardware sea detectado

## Requisitos

- **Conexión a internet por cable** (WiFi no anda hasta instalar el driver)
- **Secure Boot deshabilitado** (o firmar el módulo manualmente)
- **Kernel 6.6 ~ 6.19**
- **Arquitectura**: x86_64

### Soporte por distribución

| Distribución | Estado |
|-------------|--------|
| Fedora 40/41/42/43 | ✅ Probado |
| RHEL 9 / Rocky / Alma | ✅ Debería funcionar |
| Ubuntu 24.04+ | ✅ Debería funcionar |
| Arch Linux | ✅ Debería funcionar |
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
```

## Después de la instalación

El WiFi debería funcionar inmediatamente. Conectate con:

```bash
nmcli device wifi list                              # Listar redes
nmcli device wifi connect "MI_RED" password "CLAVE"  # Conectarse
```

**Configurá la red como autoconnect** (NetworkManager lo hace por defecto cuando te conectás).

Cuando estés listo, reiniciá y verificá que el WiFi se conecta automáticamente.

## ¿Cómo funciona a nivel técnico?

El chip MT7902 usa una arquitectura interna muy distinta a modelos anteriores (MT7921, MT7925). A diferencia de otros chips de MediaTek que comparten el mismo firmware y secuencia de inicialización, el MT7902 requiere:

- Un layout de DMA diferente en el core `mt76_connac3`
- Una secuencia específica de arranque del MCU con verificación de semáforo
- Firmware dedicado (`WIFI_MT7902_patch_mcu_1_1_hdr.bin` + `WIFI_RAM_CODE_MT7902_1.bin`)

El módulo `mt7902e.ko` empaqueta internamente todo el stack `mt76` + `mt76-connac-lib` + `mt792x-lib` + el driver específico. Esto es necesario porque los cambios son muy profundos y no es viable parchear cada sub-módulo individualmente. Por eso hay que blacklistear los módulos in-tree.

## Desinstalación

```bash
sudo bash uninstall.sh
```

## Créditos

- **[hmtheboy154](https://github.com/hmtheboy154/mt7902)** — Driver backport basado en los parches oficiales de MediaTek
- **[sean.wang@mediatek.com](mailto:sean.wang@mediatek.com)** — Parches oficiales enviados a linux-wireless (Feb 2026)
- **[checkitsnow](https://github.com/checkitsnow/MT7902_linux_drv)** — Guía de instalación y documentación
- **Comunidad** — Testing y reportes en múltiples dispositivos

## Links útiles

- [Parches oficiales en lore.kernel.org](https://lore.kernel.org/all/20260219004007.19733-1-sean.wang@kernel.org/)
- [Driver original (backport para 6.6~6.19)](https://github.com/hmtheboy154/mt7902)
- [Driver gen4 (Xiaomi BSP) - descontinuado](https://github.com/hmtheboy154/gen4-mt7902)
- [Guía alternativa (checkitsnow)](https://github.com/checkitsnow/MT7902_linux_drv)
- [Artículo CNX Software](https://www.cnx-software.com/2026/02/20/mediatek-mt7902-wireless-chipset-finally-gets-linux-drivers/)
