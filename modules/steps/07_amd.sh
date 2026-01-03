#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 7: Drivers AMD (opcional)

step_install_amd_drivers() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "7" "Drivers AMD (opcional)"

  local choice="${AMD_CHOICE:-0}"

  case "$choice" in
    1)
      info "Instalando drivers de GPU AMD (GPUs modernas: RX 400+, Vega, Navi, RDNA)..."
      echo "  • mesa (OpenGL/EGL)"
      echo "  • vulkan-radeon (Vulkan)"
      echo "  • libva-mesa-driver (aceleración de video VA-API)"
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm mesa vulkan-radeon libva-mesa-driver"
      success "Drivers de GPU AMD instalados"
      
      if confirm "¿Instalar soporte de 32-bit para juegos?"; then
        info "Habilitando repositorio multilib..."
        arch-chroot /mnt /bin/bash -c "sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf"
        arch-chroot /mnt /bin/bash -c "pacman -Sy --noconfirm"
        
        info "Instalando drivers de 32-bit..."
        arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm lib32-mesa lib32-vulkan-radeon"
        success "Soporte de 32-bit instalado"
      fi
      ;;
    2)
      info "Instalando microcode para CPU AMD..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm amd-ucode"
      success "Microcode AMD instalado"
      
      info "Regenerando configuración de GRUB..."
      arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
      success "GRUB actualizado con microcode AMD"
      ;;
    3)
      info "Instalando drivers de GPU AMD (GPUs modernas: RX 400+, Vega, Navi, RDNA)..."
      echo "  • mesa (OpenGL/EGL)"
      echo "  • vulkan-radeon (Vulkan)"
      echo "  • libva-mesa-driver (aceleración de video VA-API)"
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm mesa vulkan-radeon libva-mesa-driver"
      success "Drivers de GPU AMD instalados"
      
      if confirm "¿Instalar soporte de 32-bit para juegos?"; then
        info "Habilitando repositorio multilib..."
        arch-chroot /mnt /bin/bash -c "sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf"
        arch-chroot /mnt /bin/bash -c "pacman -Sy --noconfirm"
        
        info "Instalando drivers de 32-bit..."
        arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm lib32-mesa lib32-vulkan-radeon"
        success "Soporte de 32-bit instalado"
      fi
      
      echo
      info "Instalando microcode para CPU AMD..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm amd-ucode"
      success "Microcode AMD instalado"
      
      info "Regenerando configuración de GRUB..."
      arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
      success "GRUB actualizado con microcode AMD"
      ;;
    *)
      info "Omitiendo instalación de drivers AMD"
      ;;
  esac

  pause
}
