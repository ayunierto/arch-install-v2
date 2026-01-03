#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 3: Configurar sistema básico

step_configure_system() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "3" "Configurar sistema básico"

  [[ -n "$TIMEZONE" ]] || TIMEZONE="America/Lima"
  [[ -n "$LOCALE" ]] || LOCALE="en_US.UTF-8"
  [[ -n "$HOSTNAME" ]] || HOSTNAME="arch"

  info "Configurando zona horaria: $TIMEZONE"
  arch-chroot /mnt /bin/bash -c "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
  arch-chroot /mnt /bin/bash -c "hwclock --systohc"
  success "Zona horaria configurada"

  info "Configurando locale: $LOCALE"
  arch-chroot /mnt /bin/bash -c "echo '$LOCALE UTF-8' > /etc/locale.gen"
  arch-chroot /mnt /bin/bash -c "locale-gen"
  arch-chroot /mnt /bin/bash -c "echo 'LANG=$LOCALE' > /etc/locale.conf"
  success "Locale configurado"

  info "Configurando hostname: $HOSTNAME"
  arch-chroot /mnt /bin/bash -c "echo '$HOSTNAME' > /etc/hostname"

  arch-chroot /mnt /bin/bash -c "cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.0.1   $HOSTNAME.localdomain $HOSTNAME
EOF"
  success "Hostname configurado"
  
  pause
}
