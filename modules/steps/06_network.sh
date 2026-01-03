#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 6: Configurar red

step_configure_network() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "6" "Configurar red"

  info "Habilitando NetworkManager..."
  arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager"
  success "NetworkManager habilitado (iniciará en el próximo boot)"
}
