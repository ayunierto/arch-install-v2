#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Instalación completa de Arch Linux (UEFI) - Todo en un solo script
# ============================================================================
# Ejecutar como root en el live-ISO de Arch Linux
# Este script realiza TODA la instalación: particionado, formateo, instalación
# base, configuración del sistema, bootloader GRUB con os-prober, usuarios y red.

### VARIABLES GLOBALES ###
ROOT_PART=""
EFI_PART=""
HOME_PART=""
SWAP_PART=""
HOSTNAME=""
USERNAME=""
TIMEZONE="America/Lima"
LOCALE="es_PE.UTF-8"

### UTILIDADES ###
pause() { 
  echo
  read -rp "Presiona ENTER para continuar..." 
}

confirm() {
  local prompt="${1:-¿Continuar?}"
  local ans
  read -rp "$prompt [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

header() {
  clear
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║         Instalación Completa de Arch Linux (UEFI)              ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo
}

section() {
  echo
  echo "┌────────────────────────────────────────────────────────────────┐"
  echo "│ $1"                                                            
  echo "└────────────────────────────────────────────────────────────────┘"
  echo
}

info() {
  echo "→ $1"
}

error() {
  echo "✗ ERROR: $1" >&2
  exit 1
}

success() {
  echo "✓ $1"
}

### VERIFICACIONES INICIALES ###
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
      echo "✗ Falta comando: $c"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || error "Instala los comandos faltantes en el live-ISO"
}

### LIMPIEZA EN CASO DE ERROR ###
cleanup() {
  set +e
  if mountpoint -q /mnt 2>/dev/null; then
    info "Desmontando /mnt..."
    umount -R /mnt 2>/dev/null || true
  fi
  if [[ -n "${SWAP_PART:-}" ]]; then
    swapoff "$SWAP_PART" 2>/dev/null || true
  fi
}
trap cleanup EXIT

### SELECCIÓN DE DISCO PARA CFDISK ###
choose_disk_for_cfdisk() {
  mapfile -t disks < <(lsblk -dpno NAME,TYPE,SIZE,MODEL | awk '$2=="disk" {print $1" "$3" "$4}')
  if (( ${#disks[@]} == 0 )); then
    echo "✗ No se detectaron discos"
    pause
    return 1
  fi

  echo "Discos disponibles:"
  echo
  printf "  %-4s %-20s %-10s %-30s\n" "Idx" "DISPOSITIVO" "TAMAÑO" "MODELO"
  printf "  %-4s %-20s %-10s %-30s\n" "----" "--------------------" "----------" "------------------------------"
  for i in "${!disks[@]}"; do
    entry="${disks[$i]}"
    d_path="${entry%% *}"; rest="${entry#* }"
    d_size="${rest%% *}"; d_model="${rest#* }"
    printf "  [%2d] %-20s %-10s %-30s\n" "$((i + 1))" "$d_path" "$d_size" "${d_model:--}"
  done
  echo "  [q] Volver"
  echo
  read -rp "Elige disco para cfdisk: " choice

  [[ "$choice" == "q" ]] && return 1
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#disks[@]} )); then
    local disk_entry="${disks[$((choice - 1))]}"
    local disk_path="${disk_entry%% *}"
    cfdisk "$disk_path"
  else
    echo "✗ Selección inválida"
    pause
    return 1
  fi
}

### SELECCIÓN DE PARTICIONES ###
select_partition() {
  local label="$1"
  local varname="$2"
  local required="${3:-0}"
  
  while true; do
    header
    section "Selección de partición: $label"
    
    mapfile -t parts < <(lsblk -rpno NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT | awk '$2=="part" {print $1" "$3" "$4" "$5}')
    if (( ${#parts[@]} == 0 )); then
      echo "✗ No se detectaron particiones. Crea particiones primero con cfdisk"
      pause
      return 1
    fi

    printf "  %-4s %-24s %-10s %-12s %-12s\n" "Idx" "DISPOSITIVO" "TAMAÑO" "TIPO" "MONTADO"
    printf "  %-4s %-24s %-10s %-12s %-12s\n" "----" "------------------------" "----------" "------------" "------------"
    for i in "${!parts[@]}"; do
      entry="${parts[$i]}"
      p_path="${entry%% *}"; rest="${entry#* }"
      p_size="${rest%% *}"; rest="${rest#* }"
      p_fs="${rest%% *}"; p_mnt="${rest#* }"
      printf "  [%2d] %-24s %-10s %-12s %-12s\n" "$((i + 1))" "$p_path" "$p_size" "${p_fs:--}" "${p_mnt:--}"
    done
    
    if [[ "$required" -eq 0 ]]; then
      echo "  [0] Omitir (opcional)"
    fi
    echo "  [q] Volver al menú"
    echo
    read -rp "→ Selecciona $label: " choice

    [[ "$choice" == "q" ]] && return 1
    
    if [[ "$choice" == "0" && "$required" -eq 0 ]]; then
      info "$label: omitido"
      printf -v "$varname" '%s' ""
      pause
      return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#parts[@]} )); then
      local entry="${parts[$((choice - 1))]}"
      local part_path="${entry%% *}"
      echo
      info "Información de $part_path:"
      blkid "$part_path" || echo "  (sin formato previo)"
      echo
      if confirm "¿Confirmar $label = $part_path?"; then
        printf -v "$varname" '%s' "$part_path"
        success "$label seleccionado: $part_path"
        pause
        return 0
      fi
    else
      echo "✗ Selección inválida"
      pause
    fi
  done
}

### PASO 1: PREPARAR DISCOS ###
step_prepare_disks() {
  header
  section "PASO 1: Preparar discos y particiones"
  
  info "Este script formateará las particiones que selecciones."
  info "ADVERTENCIA: Todos los datos en esas particiones se PERDERÁN."
  echo
  confirm "¿Deseas continuar?" || exit 1

  while true; do
    header
    echo "Estado actual de discos:"
    echo
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
    echo
    echo "┌────────────────────────────────────────────────────────────────┐"
    echo "│  [1] Abrir cfdisk para crear/modificar particiones            │"
    echo "│  [2] Continuar a selección de particiones                     │"
    echo "│  [q] Salir                                                     │"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo
    read -rp "→ Opción: " opt
    
    case "$opt" in
      1) choose_disk_for_cfdisk || true ;;
      2) break ;;
      q) exit 0 ;;
      *) echo "✗ Opción inválida" ;;
    esac
  done

  # Seleccionar particiones
  select_partition "EFI (FAT32, ~512MB-1GB)" EFI_PART 1
  select_partition "ROOT (/, ext4)" ROOT_PART 1
  select_partition "HOME (/home, ext4, opcional)" HOME_PART 0
  select_partition "SWAP (opcional, tamaño RAM)" SWAP_PART 0

  [[ -n "$ROOT_PART" ]] || error "ROOT es obligatorio"
  [[ -n "$EFI_PART" ]] || error "EFI es obligatorio para UEFI"

  # Resumen
  header
  section "Resumen de particiones seleccionadas"
  echo "  EFI  : ${EFI_PART}"
  echo "  ROOT : ${ROOT_PART}"
  echo "  HOME : ${HOME_PART:-no usado}"
  echo "  SWAP : ${SWAP_PART:-no usado}"
  echo
  confirm "¿Proceder a formatear estas particiones?" || error "Cancelado por el usuario"

  # Verificar que no estén montadas
  for p in "$ROOT_PART" "$EFI_PART" ${HOME_PART:+"$HOME_PART"} ${SWAP_PART:+"$SWAP_PART"}; do
    if mountpoint -q "$p" 2>/dev/null || grep -q "^$p " /proc/mounts 2>/dev/null; then
      error "La partición $p está montada. Desmonta antes de continuar"
    fi
  done

  # Formatear
  section "Formateando particiones"
  info "Formateando EFI ($EFI_PART) como FAT32..."
  mkfs.fat -F32 "$EFI_PART"
  success "EFI formateado"

  info "Formateando ROOT ($ROOT_PART) como ext4..."
  mkfs.ext4 -F "$ROOT_PART"
  success "ROOT formateado"

  if [[ -n "$HOME_PART" ]]; then
    info "Formateando HOME ($HOME_PART) como ext4..."
    mkfs.ext4 -F "$HOME_PART"
    success "HOME formateado"
  fi

  if [[ -n "$SWAP_PART" ]]; then
    info "Creando SWAP en $SWAP_PART..."
    mkswap "$SWAP_PART"
    success "SWAP creado"
  fi

  # Montar
  section "Montando particiones en /mnt"
  mount "$ROOT_PART" /mnt
  success "ROOT montado en /mnt"

  mkdir -p /mnt/boot
  mount "$EFI_PART" /mnt/boot
  success "EFI montado en /mnt/boot"

  if [[ -n "$HOME_PART" ]]; then
    mkdir -p /mnt/home
    mount "$HOME_PART" /mnt/home
    success "HOME montado en /mnt/home"
  fi

  if [[ -n "$SWAP_PART" ]]; then
    swapon "$SWAP_PART"
    success "SWAP activado"
  fi

  echo
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
  pause
}

### PASO 2: INSTALAR SISTEMA BASE ###
step_install_base() {
  header
  section "PASO 2: Instalar sistema base"
  
  info "Se instalarán los siguientes paquetes:"
  echo "  - base, linux, linux-firmware"
  echo "  - base-devel, sudo, vim, nano"
  echo "  - networkmanager, wpa_supplicant"
  echo "  - grub, efibootmgr, os-prober, ntfs-3g"
  echo
  confirm "¿Continuar con la instalación?" || error "Cancelado"

  info "Instalando sistema base (esto puede tardar varios minutos)..."
  pacstrap -K /mnt base linux linux-firmware base-devel sudo vim nano \
    networkmanager wpa_supplicant grub efibootmgr os-prober ntfs-3g
  success "Sistema base instalado"

  info "Generando /etc/fstab..."
  genfstab -U /mnt >> /mnt/etc/fstab
  success "fstab generado"
  
  pause
}

### PASO 3: CONFIGURAR SISTEMA ###
step_configure_system() {
  header
  section "PASO 3: Configurar sistema básico"

  # Zona horaria
  echo "Zonas horarias sugeridas:"
  echo "  [1] America/Lima"
  echo "  [2] America/Mexico_City"
  echo "  [3] America/Bogota"
  echo "  [4] Europe/Madrid"
  echo "  [5] Personalizar"
  read -rp "→ Elige zona horaria [1]: " tz_opt
  case "${tz_opt:-1}" in
    1|"") TIMEZONE="America/Lima" ;;
    2) TIMEZONE="America/Mexico_City" ;;
    3) TIMEZONE="America/Bogota" ;;
    4) TIMEZONE="Europe/Madrid" ;;
    5) read -rp "Introduce zona horaria (ej: America/Santiago): " TIMEZONE ;;
  esac

  info "Configurando zona horaria: $TIMEZONE"
  arch-chroot /mnt /bin/bash -c "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
  arch-chroot /mnt /bin/bash -c "hwclock --systohc"
  success "Zona horaria configurada"

  # Locale
  echo
  echo "Locales sugeridos:"
  echo "  [1] es_PE.UTF-8"
  echo "  [2] es_ES.UTF-8"
  echo "  [3] es_MX.UTF-8"
  echo "  [4] en_US.UTF-8"
  echo "  [5] Personalizar"
  read -rp "→ Elige locale [1]: " locale_opt
  case "${locale_opt:-1}" in
    1|"") LOCALE="es_PE.UTF-8" ;;
    2) LOCALE="es_ES.UTF-8" ;;
    3) LOCALE="es_MX.UTF-8" ;;
    4) LOCALE="en_US.UTF-8" ;;
    5) read -rp "Introduce locale (ej: es_AR.UTF-8): " LOCALE ;;
  esac

  info "Configurando locale: $LOCALE"
  arch-chroot /mnt /bin/bash -c "echo '$LOCALE UTF-8' > /etc/locale.gen"
  arch-chroot /mnt /bin/bash -c "locale-gen"
  arch-chroot /mnt /bin/bash -c "echo 'LANG=$LOCALE' > /etc/locale.conf"
  success "Locale configurado"

  # Hostname
  echo
  read -rp "→ Nombre para la PC (hostname) [arch]: " HOSTNAME
  HOSTNAME="${HOSTNAME:-arch}"
  info "Configurando hostname: $HOSTNAME"
  arch-chroot /mnt /bin/bash -c "echo '$HOSTNAME' > /etc/hostname"
  arch-chroot /mnt /bin/bash -c "cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF"
  success "Hostname configurado"
  
  pause
}

### PASO 4: USUARIOS Y CONTRASEÑAS ###
step_create_users() {
  header
  section "PASO 4: Configurar usuarios"

  info "Configura la contraseña para el usuario ROOT:"
  arch-chroot /mnt /bin/bash -c "passwd"
  success "Contraseña de root establecida"

  echo
  read -rp "→ Nombre de usuario a crear [usuario]: " USERNAME
  USERNAME="${USERNAME:-usuario}"
  
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

### PASO 5: BOOTLOADER ###
step_install_bootloader() {
  header
  section "PASO 5: Instalar GRUB (bootloader)"

  info "Habilitando os-prober para detectar otros sistemas operativos (dual boot)..."
  arch-chroot /mnt /bin/bash -c "echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub"
  success "os-prober habilitado"

  info "Instalando GRUB en modo UEFI..."
  arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
  success "GRUB instalado"

  info "Detectando otros sistemas operativos..."
  arch-chroot /mnt /bin/bash -c "os-prober" || true

  info "Generando configuración de GRUB..."
  arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
  success "Configuración de GRUB generada"
  
  pause
}

### PASO 6: RED ###
step_configure_network() {
  header
  section "PASO 6: Configurar red"

  info "Habilitando NetworkManager..."
  arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager"
  success "NetworkManager habilitado (iniciará en el próximo boot)"
  
  pause
}

### PASO 7: ENTORNO DE ESCRITORIO (OPCIONAL) ###
step_install_desktop() {
  header
  section "PASO 7: Entorno de escritorio (opcional)"

  echo "¿Deseas instalar un entorno de escritorio?"
  echo "  [1] Hyprland + greetd (Wayland, moderno y fluido)"
  echo "  [2] KDE Plasma"
  echo "  [3] GNOME"
  echo "  [4] XFCE"
  echo "  [0] No instalar (solo terminal)"
  read -rp "→ Opción [0]: " de_opt

  case "${de_opt:-0}" in
    1)
      info "Instalando Hyprland + greetd + tuigreet..."
      # Paquetes base de Hyprland y Wayland
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm hyprland kitty waybar wofi xdg-desktop-portal-hyprland polkit-gnome qt5-wayland qt6-wayland seatd"
      success "Hyprland instalado"
      
      info "Habilitando seatd..."
      arch-chroot /mnt /bin/bash -c "systemctl enable seatd"
      arch-chroot /mnt /bin/bash -c "usermod -aG seat '$USERNAME'"
      success "seatd habilitado"
      
      info "Configurando greetd como gestor de sesiones..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm greetd greetd-tuigreet"
      
      # Configurar greetd para usar tuigreet y lanzar Hyprland
      arch-chroot /mnt /bin/bash -c "cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = \"tuigreet --time --remember --cmd Hyprland\"
user = \"greeter\"
EOF"
      
      arch-chroot /mnt /bin/bash -c "systemctl enable greetd"
      success "greetd configurado con tuigreet"
      
      info "Instalando herramientas adicionales para Hyprland..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm grim slurp wl-clipboard brightnessctl playerctl"
      success "Herramientas de Hyprland instaladas"
      ;;
    2)
      info "Instalando KDE Plasma..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm xorg plasma-meta sddm"
      arch-chroot /mnt /bin/bash -c "systemctl enable sddm"
      success "KDE Plasma instalado"
      ;;
    3)
      info "Instalando GNOME..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm xorg gnome gdm"
      arch-chroot /mnt /bin/bash -c "systemctl enable gdm"
      success "GNOME instalado"
      ;;
    4)
      info "Instalando XFCE..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm xorg xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
      arch-chroot /mnt /bin/bash -c "systemctl enable lightdm"
      success "XFCE instalado"
      ;;
    *)
      info "Sin entorno de escritorio. Solo terminal."
      ;;
  esac

  # Audio (PipeWire para Wayland, PulseAudio para X11)
  if [[ "${de_opt:-0}" != "0" ]]; then
    echo
    if [[ "${de_opt}" == "1" ]]; then
      info "Instalando PipeWire (recomendado para Wayland/Hyprland)..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol"
      success "PipeWire instalado"
    else
      if confirm "¿Instalar soporte de audio (PulseAudio)?"; then
        info "Instalando audio..."
        arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm alsa-utils pulseaudio pulseaudio-alsa pavucontrol"
        success "Audio instalado"
      fi
    fi
    arch-chroot /mnt /bin/bash -c "usermod -aG audio '$USERNAME'"
  fi

  # Paquetes útiles comunes
  if [[ "${de_opt:-0}" != "0" ]]; then
    echo
    if confirm "¿Instalar paquetes adicionales? (firefox, nautilus/thunar, neofetch, htop, git)"; then
      info "Instalando paquetes útiles..."
      if [[ "${de_opt}" == "1" ]]; then
        # Para Hyprland, instalar navegador y gestor de archivos compatible con Wayland
        arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm firefox nautilus neofetch htop zip unzip tar p7zip wget git"
      else
        arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm firefox thunar neofetch htop zip unzip tar p7zip wget git"
      fi
      success "Paquetes adicionales instalados"
    fi
  fi

  pause
}



### PASO FINAL ###
step_finalize() {
  header
  section "¡INSTALACIÓN COMPLETADA!"

  success "Arch Linux ha sido instalado exitosamente"
  echo
  echo "Configuración:"
  echo "  • Hostname: $HOSTNAME"
  echo "  • Usuario: $USERNAME"
  echo "  • Timezone: $TIMEZONE"
  echo "  • Locale: $LOCALE"
  echo "  • Bootloader: GRUB (UEFI) con os-prober habilitado"
  echo "  • Red: NetworkManager"
  echo
  echo "Próximos pasos:"
  echo "  1. Sal del instalador: exit"
  echo "  2. Desmonta las particiones: umount -R /mnt"
  echo "  3. Desactiva swap (si usaste): swapoff -a"
  echo "  4. Reinicia: reboot"
  echo "  5. Retira el USB/ISO y arranca desde el disco"
  echo
  info "Después del primer arranque, inicia sesión con tu usuario y configura"
  info "lo que necesites (escritorio, aplicaciones, etc.)"
  echo
  
  if confirm "¿Desmontar /mnt y reiniciar ahora?"; then
    info "Desmontando..."
    umount -R /mnt || true
    swapoff -a 2>/dev/null || true
    info "Reiniciando en 5 segundos..."
    sleep 5
    reboot
  else
    info "No olvides desmontar y reiniciar manualmente cuando termines"
  fi
}

### MAIN ###
main() {
  header
  info "Iniciando instalador de Arch Linux..."
  echo
  
  check_root
  check_uefi
  check_commands
  
  pause

  step_prepare_disks
  step_install_base
  step_configure_system
  step_create_users
  step_install_bootloader
  step_configure_network
  step_install_desktop
  step_finalize
}

main "$@"
