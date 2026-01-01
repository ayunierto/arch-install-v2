#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Arch Install Guided - paso 2: bootloader GRUB (UEFI) con os-prober habilitado
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
  echo " Arch Linux – Bootloader (GRUB UEFI)"
  echo "======================================"
  echo
}

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

check_commands() {
  local cmds=(grub-install grub-mkconfig os-prober)
  for c in "${cmds[@]}"; do
    command -v "$c" &>/dev/null || error "Falta comando: $c (instala el paquete correspondiente)"
  done
}

ensure_env() {
  [[ $EUID -eq 0 ]] || error "Ejecuta como root"
  [[ -d /sys/firmware/efi ]] || error "UEFI no detectado; este script asume UEFI"
  mountpoint -q /boot/efi || error "/boot/efi no está montado"
  [[ -f /etc/locale.gen ]] || error "Parece que no estás en el chroot de Arch (/etc/locale.gen falta)"
}

enable_os_prober() {
  echo "Habilitando os-prober en /etc/default/grub ..."
  local grub_file=/etc/default/grub
  [[ -f "$grub_file" ]] || touch "$grub_file"
  if grep -q "^#*GRUB_DISABLE_OS_PROBER" "$grub_file"; then
    sed -i 's/^#*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$grub_file"
  else
    echo "GRUB_DISABLE_OS_PROBER=false" >> "$grub_file"
  fi
}

install_grub() {
  echo "Instalando GRUB en modo UEFI ..."
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
}

gen_grub_cfg() {
  echo "Generando /boot/grub/grub.cfg ..."
  grub-mkconfig -o /boot/grub/grub.cfg
}

header
ensure_env
check_commands
enable_os_prober
confirm "Continuar con grub-install y grub-mkconfig?" || error "Cancelado"
install_grub
gen_grub_cfg

echo
echo "GRUB instalado y os-prober habilitado."
echo "Si Dual Boot, asegúrate de que Windows esté presente y vuelve a correr grub-mkconfig si cambias discos."
echo
exit 0
