#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Arch Install Guided - paso 3: locale, hostname, usuario, NetworkManager
# Ejecutar dentro del chroot de /mnt.

confirm() {
  local prompt="${1:-¿Continuar?}"
  local default="${2:-N}"
  local ans
  read -rp "$prompt [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

header() {
  clear
  echo "======================================"
  echo " Arch Linux – Configuración básica"
  echo "======================================"
  echo
}

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

check_env() {
  [[ $EUID -eq 0 ]] || error "Ejecuta como root"
  [[ -f /etc/locale.gen ]] || error "No parece un chroot de Arch (falta /etc/locale.gen)"
}

set_timezone() {
  echo "Zona horaria sugeridas:"
  echo "  [1] America/Mexico_City"
  echo "  [2] America/Bogota"
  echo "  [3] Europe/Madrid"
  echo "  [4] America/Santiago"
  echo "  [5] Personalizar"
  echo
  read -rp "Elige zona (1-5) [1]: " tz_opt
  case "${tz_opt:-1}" in
    1|"" ) TZ_CHOSEN="America/Mexico_City" ;;
    2 ) TZ_CHOSEN="America/Bogota" ;;
    3 ) TZ_CHOSEN="Europe/Madrid" ;;
    4 ) TZ_CHOSEN="America/Santiago" ;;
    5 ) read -rp "Introduce TZ (ej: America/Argentina/Buenos_Aires): " TZ_CHOSEN ;;
    * ) TZ_CHOSEN="America/Mexico_City" ;;
  esac
  [[ -n "$TZ_CHOSEN" ]] || error "TZ vacío"
  ln -sf "/usr/share/zoneinfo/$TZ_CHOSEN" /etc/localtime
  hwclock --systohc
}

set_locale() {
  echo "Activando locales en /etc/locale.gen (en_US y es_ES)..."
  sed -i 's/^#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  sed -i 's/^#\s*es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  echo "Idioma por defecto para el sistema:"
  echo "  [1] en_US.UTF-8"
  echo "  [2] es_ES.UTF-8"
  read -rp "Elige [1/2] [1]: " lang_opt
  case "${lang_opt:-1}" in
    2 ) LANG_CHOSEN="es_ES.UTF-8" ;;
    * ) LANG_CHOSEN="en_US.UTF-8" ;;
  esac
  echo "LANG=$LANG_CHOSEN" > /etc/locale.conf
}

set_hostname() {
  read -rp "Hostname [archlinux]: " hostn
  hostn="${hostn:-archlinux}"
  echo "$hostn" > /etc/hostname
  cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostn.localdomain $hostn
EOF
}

set_root_pass() {
  echo "Define contraseña para root:"
  passwd
}

create_user() {
  read -rp "Nombre de usuario (minúsculas) [usuario]: " newuser
  newuser="${newuser:-usuario}"
  id -u "$newuser" &>/dev/null || useradd -m -G wheel -s /bin/bash "$newuser"
  echo "Contraseña para $newuser:" && passwd "$newuser"
  echo "Habilitando sudo para grupo wheel..."
  sed -i 's/^#\s*%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
}

enable_networkmanager() {
  systemctl enable NetworkManager
}

header
check_env
set_timezone
set_locale
set_hostname
set_root_pass
create_user
enable_networkmanager

echo
echo "Configuración básica completada. Puedes instalar escritorios/paquetes adicionales y reiniciar."
echo
exit 0
