#!/usr/bin/env bash
# shellcheck shell=bash
# Verificación final

step_verify_installation() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "9" "Verificación final de la instalación"
  
  local errors=0
  
  info "Verificando componentes críticos..."
  echo
  
  # Verificar fstab
  if grep -q "/boot" /mnt/etc/fstab; then
    success "/boot está en fstab"
  else
    warn "/boot NO está en fstab"
    errors=$((errors + 1))
  fi
  
  # Verificar GRUB
  if [[ -f /mnt/boot/grub/grub.cfg ]]; then
    success "grub.cfg existe"
  else
    warn "grub.cfg NO existe"
    errors=$((errors + 1))
  fi
  
  if [[ -d /mnt/boot/EFI/Arch ]]; then
    success "Bootloader UEFI instalado en /boot/EFI/Arch"
  else
    warn "Bootloader NO está en /boot/EFI/"
    errors=$((errors + 1))
  fi
  
  # Verificar kernel
  if ls /mnt/boot/vmlinuz-* &>/dev/null; then
    success "Kernel instalado en /boot"
  else
    warn "Kernel NO está en /boot"
    errors=$((errors + 1))
  fi
  
  # Verificar initramfs
  if ls /mnt/boot/initramfs-* &>/dev/null; then
    success "initramfs instalado en /boot"
  else
    warn "initramfs NO está en /boot"
    errors=$((errors + 1))
  fi
  
  echo
  if [[ $errors -gt 0 ]]; then
    warn "SE DETECTARON $errors ERROR(ES) CRÍTICO(S)"
    echo "  La instalación puede no arrancar correctamente."
    echo "  Revisa los errores antes de reiniciar."
    pause
  else
    success "Todas las verificaciones pasaron correctamente"
  fi
  
  pause
}
