#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'



# ============================================================================
# Instalación completa de Arch Linux (UEFI) - Todo en un solo script
# ============================================================================
# Ejecutar como root en el live-ISO de Arch Linux
# Este script realiza TODA la instalación: particionado, formateo, instalación
# base, configuración del sistema, bootloader GRUB con os-prober, usuarios y red.

# Configurar fuente de consola para mejor legibilidad
setfont ter-132b

### VARIABLES GLOBALES ###
ROOT_PART=""
EFI_PART=""
HOME_PART=""
SWAP_PART=""
HOSTNAME=""
USERNAME=""
TIMEZONE="America/Lima"
LOCALE="en_US.UTF-8"

### UTILIDADES ###
pause() { 
  echo
  read -rp "Presiona ENTER para continuar..." 
}

### Pregunta de confirmación (sí/no)
confirm() {
  local prompt="${1:-¿Continuar?}"
  local ans
  read -rp "$prompt [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

### Encabezado del script
header() {
  clear
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║         Instalación Completa de Arch Linux (UEFI)              ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo
}

### Sección del script
section() {
  echo
  echo "┌────────────────────────────────────────────────────────────────┐"
  echo "│ $1"                                                            
  echo "└────────────────────────────────────────────────────────────────┘"
  echo
}

### Mensajes informativos
info() {
  echo "→ $1"
}

### Mensajes de error y salida
error() {
  echo "✗ ERROR: $1" >&2
  exit 1
}

### Mensajes de éxito
success() {
  echo "✓ $1"
}

### VERIFICACIONES INICIALES ###
check_root() {
  [[ $EUID -eq 0 ]] || error "Este script debe ejecutarse como root"
}

### Verificar modo UEFI
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
    echo "│  [1] Abrir cfdisk para crear/modificar particiones             │"
    echo "│  [2] Continuar a selección de particiones                      │"
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
  
  # Preguntar si formatear EFI (en dual boot normalmente NO se formatea)
  echo "IMPORTANTE: Si estás haciendo dual boot (por ejemplo con Windows),"
  echo "la partición EFI ya existe y contiene archivos del otro sistema."
  echo "¡Formatearla ELIMINARÁ el bootloader del otro sistema operativo!"
  echo
  if confirm "¿Formatear partición EFI ($EFI_PART) como FAT32?"; then
    info "Formateando EFI ($EFI_PART) como FAT32..."
    mkfs.fat -F32 "$EFI_PART"
    success "EFI formateado"
  else
    info "Partición EFI NO será formateada (se usará la existente)"
    # Verificar que la partición tenga un sistema de archivos válido
    if ! blkid "$EFI_PART" | grep -q "TYPE=\"vfat\""; then
      echo "✗ ADVERTENCIA: La partición EFI no parece tener formato FAT32"
      echo "  Esto puede causar problemas al instalar GRUB"
      if ! confirm "¿Continuar de todas formas?"; then
        error "Cancelado por el usuario"
      fi
    fi
  fi

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

  # 1.11 Montar
  section "Montando particiones en /mnt"
  mount "$ROOT_PART" /mnt
  success "ROOT montado en /mnt"

  mount --mkdir "$EFI_PART" /mnt/boot
  success "EFI montado en /mnt/boot"
  
  # Verificar que el montaje fue exitoso
  if ! mountpoint -q /mnt/boot; then
    error "CRÍTICO: /mnt/boot no está montado correctamente"
  fi
  
  # Verificar que la partición EFI es accesible
  if ! touch /mnt/boot/.test 2>/dev/null; then
    error "CRÍTICO: No se puede escribir en /mnt/boot (permisos o sistema de archivos corrupto)"
  fi
  rm -f /mnt/boot/.test

  if [[ -n "$HOME_PART" ]]; then
    mount --mkdir "$HOME_PART" /mnt/home
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

  # Localización (locale)
  echo
  echo "Locales sugeridos:"
  echo "  [1] en_US.UTF-8"
  echo "  [2] es_PE.UTF-8"
  echo "  [3] es_ES.UTF-8"
  echo "  [4] es_MX.UTF-8"
  echo "  [5] Personalizar"
  read -rp "→ Elige locale [1]: " locale_opt
  case "${locale_opt:-1}" in
    1|"") LOCALE="en_US.UTF-8" ;;
    2) LOCALE="es_PE.UTF-8" ;;
    3) LOCALE="es_ES.UTF-8" ;;
    4) LOCALE="es_MX.UTF-8" ;;
    5) read -rp "Introduce locale (ej: es_AR.UTF-8): " LOCALE ;;
  esac

  info "Configurando locale: $LOCALE"
  arch-chroot /mnt /bin/bash -c "echo '$LOCALE UTF-8' > /etc/locale.gen"
  arch-chroot /mnt /bin/bash -c "locale-gen"
  arch-chroot /mnt /bin/bash -c "echo 'LANG=$LOCALE' > /etc/locale.conf"
  success "Locale configurado"

  # Network configuration
  # Hostname
  echo
  read -rp "→ Nombre para la PC (hostname) [arch]: " HOSTNAME
  HOSTNAME="${HOSTNAME:-arch}"
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
  if ! arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch"; then
    error "CRÍTICO: La instalación de GRUB falló. Verifica que /boot esté correctamente montado."
  fi
  success "GRUB instalado"
  
  # Verificar que los archivos de GRUB existan
  if [[ ! -f /mnt/boot/grub/grubenv ]]; then
    echo "✗ ADVERTENCIA: No se encontraron archivos de GRUB en /mnt/boot/grub/"
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
    echo "✗ ADVERTENCIA: No se encontraron entradas de menú en grub.cfg"
    pause
  fi
  
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

### PASO 7: DRIVERS AMD (OPCIONAL) ###
step_install_amd_drivers() {
  header
  section "PASO 7: Drivers AMD (opcional)"

  echo "¿Tu sistema tiene hardware AMD (CPU o GPU)?"
  echo
  echo "  [1] GPU AMD (instalar drivers de gráficos)"
  echo "  [2] CPU AMD (instalar microcode)"
  echo "  [3] Ambos (GPU + CPU AMD)"
  echo "  [0] Omitir (no tengo hardware AMD)"
  read -rp "→ Opción [0]: " amd_opt

  case "${amd_opt:-0}" in
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

### PASO 8: ENTORNO DE ESCRITORIO (OPCIONAL) ###
step_install_desktop() {
  header
  section "PASO 8: Entorno de escritorio (opcional)"

  echo "¿Deseas instalar un entorno de escritorio?"
  echo "  [1] Hyprland + greetd (Wayland, moderno y fluido)"
  echo "  [2] GNOME (Wayland + X11, completo)"
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
  if [[ "${de_opt:-0}" != "0" ]]; then
    echo
    if [[ "${de_opt}" == "1" ]]; then
      info "Instalando PipeWire (recomendado para Wayland/Hyprland)..."
      arch-chroot /mnt /bin/bash -c "pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol"
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



### VERIFICACIÓN FINAL ###
step_verify_installation() {
  header
  section "VERIFICACIÓN FINAL DE LA INSTALACIÓN"
  
  local errors=0
  
  info "Verificando componentes críticos..."
  echo
  
  # Verificar fstab
  if grep -q "/boot" /mnt/etc/fstab; then
    success "/boot está en fstab"
  else
    echo "✗ ERROR: /boot NO está en fstab"
    errors=$((errors + 1))
  fi
  
  # Verificar GRUB
  if [[ -f /mnt/boot/grub/grub.cfg ]]; then
    success "grub.cfg existe"
  else
    echo "✗ ERROR: grub.cfg NO existe"
    errors=$((errors + 1))
  fi
  
  if [[ -d /mnt/boot/EFI/Arch ]]; then
    success "Bootloader UEFI instalado en /boot/EFI/Arch"
  else
    echo "✗ ERROR: Bootloader NO está en /boot/EFI/"
    errors=$((errors + 1))
  fi
  
  # Verificar kernel
  if ls /mnt/boot/vmlinuz-* &>/dev/null; then
    success "Kernel instalado en /boot"
  else
    echo "✗ ERROR: Kernel NO está en /boot"
    errors=$((errors + 1))
  fi
  
  # Verificar initramfs
  if ls /mnt/boot/initramfs-* &>/dev/null; then
    success "initramfs instalado en /boot"
  else
    echo "✗ ERROR: initramfs NO está en /boot"
    errors=$((errors + 1))
  fi
  
  echo
  if [[ $errors -gt 0 ]]; then
    echo "⚠ SE DETECTARON $errors ERROR(ES) CRÍTICO(S)"
    echo "  La instalación puede no arrancar correctamente."
    echo "  Revisa los errores antes de reiniciar."
    pause
  else
    success "Todas las verificaciones pasaron correctamente"
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
  
  info "Sincronizando reloj del sistema..."
  timedatectl
  success "Reloj sincronizado"
  
  pause

  step_prepare_disks
  step_install_base
  step_configure_system
  step_create_users
  step_install_bootloader
  step_configure_network
  step_install_amd_drivers
  step_install_desktop
  step_verify_installation
  step_finalize
}

main "$@"
