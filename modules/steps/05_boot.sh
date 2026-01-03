#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 5: Bootloader GRUB

step_install_bootloader() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "5" "Instalar GRUB (bootloader)"

  info "Habilitando os-prober para detectar otros sistemas operativos (dual boot)..."
  arch-chroot /mnt /bin/bash -c "echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub"
  success "os-prober habilitado"

  info "Instalando GRUB en modo UEFI..."
  if ! arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch"; then
    error "CRÍTICO: La instalación de GRUB falló. Verifica que /boot esté correctamente montado."
  fi
  success "GRUB instalado"
  
  # Verificar que los archivos de GRUB existan
  if [[ ! -f /mnt/boot/grub/grubenv ]]; then
    warn "No se encontraron archivos de GRUB en /mnt/boot/grub/"
    echo "  Esto puede indicar un problema con la partición EFI."
    if ! confirm "¿Continuar de todas formas?"; then
      error "Instalación cancelada. Verifica la partición EFI."
    fi
  fi

  info "Detectando otros sistemas operativos..."
  arch-chroot /mnt /bin/bash -c "os-prober" || true

  info "Generando configuración de GRUB..."
  arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
  success "Configuración de GRUB generada"
  
  # Verificar que grub.cfg se haya generado correctamente
  if [[ ! -s /mnt/boot/grub/grub.cfg ]]; then
    error "CRÍTICO: El archivo grub.cfg está vacío o no existe."
  fi
  
  info "Verificando entradas de arranque..."
  if grep -q "menuentry" /mnt/boot/grub/grub.cfg; then
    success "Configuración de GRUB válida (entradas de menú encontradas)"
  else
    warn "No se encontraron entradas de menú en grub.cfg"
    pause
  fi
  
  pause
}
