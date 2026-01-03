#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 8: Entorno de escritorio (opcional)

step_install_desktop() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "8" "Entorno de escritorio (opcional)"

  local choice="${DESKTOP_CHOICE:-0}"

  case "$choice" in
    1)
      info "Instalando Hyprland + greetd + tuigreet..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm hyprland kitty waybar wofi xdg-desktop-portal-hyprland polkit-gnome qt5-wayland qt6-wayland seatd"
      success "Hyprland instalado"
      
      info "Habilitando seatd..."
      arch-chroot /mnt /bin/bash -c "systemctl enable seatd"
      arch-chroot /mnt /bin/bash -c "usermod -aG seat '$USERNAME'"
      success "seatd habilitado"
      
      info "Configurando greetd como gestor de sesiones..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm greetd greetd-tuigreet"
      
      arch-chroot /mnt /bin/bash -c "cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = \"tuigreet --time --remember --cmd Hyprland\"
user = \"greeter\"
EOF"
      
      arch-chroot /mnt /bin/bash -c "systemctl enable greetd"
      success "greetd configurado con tuigreet (Hyprland generará su config al primer arranque)"
      
      info "Instalando herramientas adicionales para Hyprland..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm grim slurp wl-clipboard brightnessctl playerctl"
      success "Herramientas de Hyprland instaladas"
      ;;
    2)
      info "Instalando GNOME..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm gnome gdm"
      arch-chroot /mnt /bin/bash -c "systemctl enable gdm"
      success "GNOME instalado"
      ;;
    *)
      info "Sin entorno de escritorio. Solo terminal."
      ;;
  esac

  # Audio (PipeWire para Wayland, PulseAudio para X11)
  if [[ "$choice" != "0" && "${DO_AUDIO:-no}" == "yes" ]]; then
    echo
    if [[ "$choice" == "1" ]]; then
      info "Instalando PipeWire (recomendado para Wayland/Hyprland)..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol"
      success "PipeWire instalado"
    else
      info "Instalando audio (PulseAudio)..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm alsa-utils pulseaudio pulseaudio-alsa pavucontrol"
      success "Audio instalado"
    fi
    arch-chroot /mnt /bin/bash -c "usermod -aG audio '$USERNAME'"
  fi

  # Paquetes útiles comunes
  if [[ "$choice" != "0" && "${DO_EXTRA_PKGS:-no}" == "yes" ]]; then
    echo
    info "Instalando paquetes adicionales..."
    if [[ "$choice" == "1" ]]; then
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm firefox nautilus neofetch htop zip unzip tar p7zip wget git"
    else
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm firefox thunar neofetch htop zip unzip tar p7zip wget git"
    fi
    success "Paquetes adicionales instalados"
  fi

  pause
}
