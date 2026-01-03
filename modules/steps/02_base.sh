#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 2: Instalar sistema base

step_install_base() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "2" "Instalar sistema base"
  
  info "Instalando paquetes base (esto puede tardar varios minutos)..."
  echo "  - base, linux, linux-firmware"
  echo "  - base-devel, sudo, neovim"
  echo "  - networkmanager, wpa_supplicant"
  echo "  - grub, efibootmgr, os-prober, ntfs-3g"
  echo

  pacstrap -K /mnt base linux linux-firmware base-devel sudo neovim \
    networkmanager wpa_supplicant grub efibootmgr os-prober ntfs-3g 
  success "Sistema base instalado"

  info "Generando /etc/fstab..."
  genfstab -U /mnt >> /mnt/etc/fstab
  success "fstab generado"
  echo
  
  # Verificar que /boot esté en fstab
  if ! grep -q "/boot" /mnt/etc/fstab; then
    error "CRÍTICO: /boot no está en /etc/fstab. La instalación falló."
  fi
  
  # Mostrar fstab generado
  info "Contenido de /etc/fstab:"
  echo
  cat /mnt/etc/fstab
  echo
  
  # Advertencia importante
  echo "⚠ IMPORTANTE: Verifica que la línea de /boot tenga el UUID correcto"
  echo "             Si hay algún problema, edita /mnt/etc/fstab antes de continuar"
  echo
  pause
}
