#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 4: Configurar usuarios

step_create_users() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "4" "Configurar usuarios"

  info "Configura la contraseña para el usuario ROOT:"
  arch-chroot /mnt /bin/bash -c "passwd"
  success "Contraseña de root establecida"

  echo
  [[ -n "$USERNAME" ]] || USERNAME="usuario"
  info "Usuario a crear: $USERNAME"
  
  info "Creando usuario: $USERNAME"
  arch-chroot /mnt /bin/bash -c "useradd -m -G wheel '$USERNAME'"
  
  echo
  info "Configura la contraseña para $USERNAME:"
  arch-chroot /mnt /bin/bash -c "passwd '$USERNAME'"
  success "Usuario $USERNAME creado"

  info "Habilitando sudo para el grupo wheel..."
  arch-chroot /mnt /bin/bash -c "sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
  success "Sudo habilitado para wheel"
  
  pause
}
