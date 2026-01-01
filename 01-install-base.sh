#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Arch Install Guided - paso 1: instalar base en /mnt
# Ejecutar como root en live-ISO, con /mnt ya montado (00-disk-setup.sh).

PKGS_DEFAULT=(base linux linux-firmware sudo vim nano networkmanager grub os-prober)

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
  echo " Arch Linux – Instalar base (/mnt)"
  echo "======================================"
  echo
}

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

check_commands() {
  local cmds=(pacstrap genfstab)
  for c in "${cmds[@]}"; do
    if ! command -v "$c" &>/dev/null; then
      echo "Falta comando requerido: $c"
      missing=1
    fi
  done
  [[ ${missing:-0} -eq 1 ]] && error "Instala los comandos faltantes en el live-ISO."
}

ensure_mnt_ready() {
  mountpoint -q /mnt || error "/mnt no está montado. Ejecuta primero 00-disk-setup.sh"
}

choose_packages() {
  echo "Paquetes a instalar (pacstrap -K /mnt ...):"
  for p in "${PKGS_DEFAULT[@]}"; do
    echo "  - $p"
  done
  echo "Puedes añadir extras separados por espacio (o deja vacío para usar solo la lista sugerida):"
  read -rp "Extras: " extras || true
  PKGS=("${PKGS_DEFAULT[@]}")
  if [[ -n "${extras:-}" ]]; then
    # shellcheck disable=SC2206
    extra_array=( $extras )
    PKGS+=("${extra_array[@]}")
  fi
  echo
  echo "Paquetes finales: ${PKGS[*]}"
  confirm "¿Usar esta lista?" || error "Cancelado."
}

run_pacstrap() {
  echo "Instalando base en /mnt ..."
  pacstrap -K /mnt "${PKGS[@]}"
}

gen_fstab() {
  echo "Generando /mnt/etc/fstab ..."
  mkdir -p /mnt/etc
  if [[ -f /mnt/etc/fstab ]]; then
    cp /mnt/etc/fstab "/mnt/etc/fstab.backup.$(date +%s)"
  fi
  genfstab -U /mnt > /mnt/etc/fstab
}

header
[[ $EUID -eq 0 ]] || error "Ejecuta como root"
check_commands
ensure_mnt_ready
choose_packages
run_pacstrap
gen_fstab

echo
echo "Base instalada. Pasos siguientes sugeridos:"
echo "- arch-chroot /mnt"
echo "- Ejecutar dentro del chroot: /root/02-bootloader.sh y /root/03-users.sh (cópialos si no están)."
echo "- Configurar mirrors, keyring u otros según necesidad."
echo
exit 0
