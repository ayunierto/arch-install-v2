#!/usr/bin/env bash
# shellcheck shell=bash
# Validaciones y verificaciones previas

check_root() {
  [[ $EUID -eq 0 ]] || error "Este script debe ejecutarse como root"
}

check_uefi() {
  [[ -d /sys/firmware/efi ]] || error "Sistema UEFI no detectado. Arranca el ISO en modo UEFI"
}

check_commands() {
  local cmds=(lsblk cfdisk mkfs.fat mkfs.ext4 mkswap swapon mount blkid pacstrap genfstab arch-chroot)
  local missing=0
  for c in "${cmds[@]}"; do
    if ! command -v "$c" &>/dev/null; then
      warn "Falta comando: $c"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || error "Instala los comandos faltantes en el live-ISO"
}
