# Instalador Arch Linux (UEFI) - Todo en Uno

Script completo y guiado para instalar **Arch Linux** en sistemas UEFI desde el live-ISO oficial. Interfaz amigable con menús numéricos y confirmaciones de seguridad.

## 🎯 Características

- ✅ **Instalación completa end-to-end**: desde particionado hasta sistema listo para usar
- 🖥️ **Interfaz intuitiva**: menús con cajas ASCII, selección numérica (sin teclear rutas `/dev/...`)
- 🔒 **Seguridad**: confirmaciones dobles antes de formatear, trap de limpieza automática
- 🌐 **Dual-boot**: GRUB con `os-prober` habilitado para detectar Windows automáticamente
- 🎨 **Hyprland incluido**: compositor Wayland moderno con greetd + tuigreet + PipeWire
- 🛠️ **Sin intervención manual**: toda la configuración se hace con `arch-chroot` desde el ISO

## 📋 Requisitos previos

- **Sistema**: máquina con UEFI (no BIOS legacy)
- **ISO**: Arch Linux live-ISO oficial (descarga desde [archlinux.org](https://archlinux.org/download/))
- **Arranque**: iniciar en modo UEFI (no CSM/Legacy)
- **Red**: conexión a Internet activa (el script verifica al inicio)
- **VirtualBox/Hardware**: si pruebas en VM, habilita "Enable EFI" en configuración

## 🚀 Uso rápido

### 1. Arranca el live-ISO

Inicia desde el USB/ISO de Arch Linux en modo UEFI. Deberías ver el prompt:

```bash
root@archiso ~ #
```

### 2. Descarga el script

```bash
# Opción 1: cURL
curl -LO https://raw.githubusercontent.com/TU-USUARIO/arch-install-v2/main/install-unified.sh

# Opción 2: wget
wget https://raw.githubusercontent.com/TU-USUARIO/arch-install-v2/main/install-unified.sh
```

### 3. Dale permisos de ejecución

```bash
chmod +x install-unified.sh
```

### 4. Ejecuta el instalador

```bash
./install-unified.sh
```

### 5. Sigue los pasos guiados

El script te llevará por 7 pasos:

1. **Preparar discos**: crea particiones con `cfdisk`, luego selecciona EFI/ROOT/HOME/SWAP por número
2. **Instalar base**: `pacstrap` con kernel, NetworkManager, GRUB, os-prober, etc.
3. **Configurar sistema**: zona horaria, locale, hostname (con menús)
4. **Crear usuarios**: contraseña root + usuario con sudo
5. **Instalar GRUB**: bootloader UEFI con dual-boot habilitado
6. **Configurar red**: habilita NetworkManager
7. **Escritorio opcional**: Hyprland/KDE/GNOME/XFCE o solo terminal

Al final, opción de desmontar y reiniciar automáticamente.

## 🎨 Entornos de escritorio disponibles

### 1. Hyprland (Recomendado para Wayland)

- **Compositor**: Hyprland (dinámico tiling, Wayland)
- **Gestor de sesiones**: greetd + tuigreet (TUI elegante)
- **Terminal**: kitty
- **Audio**: PipeWire (nativo Wayland)
- **Herramientas**: waybar, wofi, grim, slurp, wl-clipboard, brightnessctl, playerctl
- **Portales**: xdg-desktop-portal-hyprland, polkit-gnome
- **Seat management**: seatd (usuario añadido al grupo `seat`)

### 2. KDE Plasma

- Entorno completo con Wayland y X11, gestor SDDM

### 3. GNOME

- Entorno moderno con GDM

### 4. XFCE

- Entorno ligero con LightDM

## 📦 Paquetes instalados

### Base

- `base`, `linux`, `linux-firmware`
- `base-devel`, `sudo`, `vim`, `nano`
- `networkmanager`, `wpa_supplicant`
- `grub`, `efibootmgr`, `os-prober`, `ntfs-3g`

### Hyprland (si se elige opción 1)

- `hyprland`, `kitty`, `waybar`, `wofi`
- `xdg-desktop-portal-hyprland`, `polkit-gnome`
- `qt5-wayland`, `qt6-wayland`, `seatd`
- `greetd`, `greetd-tuigreet`
- `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack`, `wireplumber`, `pavucontrol`
- `grim`, `slurp`, `wl-clipboard`, `brightnessctl`, `playerctl`

### Opcionales (si confirmas)

- `firefox`, `nautilus` (Wayland) o `thunar` (X11)
- `neofetch`, `htop`, `git`, `zip`, `unzip`, `tar`, `p7zip`, `wget`

## 🛡️ Seguridad y confirmaciones

- ❌ **Defecto = NO**: todas las confirmaciones tienen `[y/N]` (default a NO)
- ⚠️ **Doble confirmación**: antes de formatear, el script muestra las particiones y pide confirmar dos veces
- 🧹 **Limpieza automática**: si el script falla, desmonta `/mnt` y desactiva swap automáticamente
- 🔍 **Verificación previa**: chequea que particiones no estén montadas antes de formatear

## 📂 Esquema de particiones recomendado

Para crear con `cfdisk` (GPT):

| Partición   | Tamaño      | Tipo             | Uso             |
| ----------- | ----------- | ---------------- | --------------- |
| `/dev/sdX1` | 512MB-1GB   | EFI System       | EFI             |
| `/dev/sdX2` | Igual a RAM | Linux swap       | SWAP            |
| `/dev/sdX3` | 30-50GB     | Linux filesystem | ROOT (/)        |
| `/dev/sdX4` | Resto       | Linux filesystem | HOME (opcional) |

**Nota**: HOME es opcional; si la omites, los datos de usuarios van en ROOT.

## 🖥️ Post-instalación (después del primer boot)

### Si instalaste Hyprland

1. Inicia sesión en `tuigreet` (usuario que creaste)
2. Se abre Hyprland automáticamente
3. Abre kitty (terminal): `Super + Enter`
4. Configurar Hyprland: edita `~/.config/hypr/hyprland.conf`

### Comandos útiles post-instalación

```bash
# Conectar a WiFi
nmtui

# Instalar AUR helper (yay)
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si

# Actualizar sistema
sudo pacman -Syu

# Instalar fuentes
sudo pacman -S ttf-dejavu ttf-liberation noto-fonts
```

## 🧪 Pruebas en VirtualBox

1. Crea VM con:

   - **System → Enable EFI** ✅
   - Disco virtual (20GB mínimo)
   - RAM (2GB mínimo)
   - Red: NAT (para Internet automático)

2. Monta ISO de Arch como disco óptico

3. Arranca y sigue el flujo normal del script

4. Una vez instalado, desmonta el ISO y reinicia

## 🐛 Solución de problemas

### "Sistema UEFI no detectado"

- Verifica que arrancaste en modo UEFI (no Legacy/CSM)
- En VirtualBox: Settings → System → Enable EFI debe estar marcado

### "No hay conexión a Internet"

```bash
# Conectar a Ethernet
dhcpcd

# Conectar a WiFi
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "NOMBRE-RED"
```

### "Falta comando: pacstrap"

- Asegúrate de estar en el live-ISO oficial de Arch, no otra distro

### GRUB no detecta Windows

- Verifica que Windows exista en otra partición antes de correr el script
- `os-prober` ejecuta automáticamente durante la instalación
- Si falla, después del boot: `sudo grub-mkconfig -o /boot/grub/grub.cfg`

## 📝 Licencia

MIT License - Úsalo, modifícalo y compártelo libremente.

## 🤝 Contribuciones

PRs bienvenidos para:

- Soporte BIOS legacy
- Más entornos de escritorio
- Mejoras en la detección de hardware
- Traducción a otros idiomas

## ⚠️ Disclaimer

Este script **formatea particiones**. Úsalo bajo tu responsabilidad. Siempre prueba primero en una VM antes de usar en hardware real.

---

**Autor**: Tu nombre  
**Fecha**: 2026  
**Versión**: 1.0
