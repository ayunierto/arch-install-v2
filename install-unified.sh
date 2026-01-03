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

  fi
  #!/usr/bin/env bash
  set -euo pipefail
  IFS=$'\n\t'

  # ============================================================================
  # Instalación completa de Arch Linux (UEFI) - Orquestador modular
  # Ejecutar como root en el live-ISO de Arch Linux
  # ============================================================================

  # Configurar fuente de consola para mejor legibilidad
  setfont ter-132b

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  ### VARIABLES GLOBALES ###
  ROOT_PART=""
  EFI_PART=""
  HOME_PART=""
  SWAP_PART=""
  HOSTNAME=""
  USERNAME=""
  TIMEZONE="America/Lima"
  LOCALE="en_US.UTF-8"

  ### CARGA DE MÓDULOS ###
  source "${SCRIPT_DIR}/modules/ui.sh"
  source "${SCRIPT_DIR}/modules/validation.sh"
  source "${SCRIPT_DIR}/modules/steps/01_disks.sh"
  source "${SCRIPT_DIR}/modules/plan.sh"
  source "${SCRIPT_DIR}/modules/steps/02_base.sh"
  source "${SCRIPT_DIR}/modules/steps/03_config.sh"
  source "${SCRIPT_DIR}/modules/steps/04_users.sh"
  source "${SCRIPT_DIR}/modules/steps/05_boot.sh"
  source "${SCRIPT_DIR}/modules/steps/06_network.sh"
  source "${SCRIPT_DIR}/modules/steps/07_amd.sh"
  source "${SCRIPT_DIR}/modules/steps/08_desktop.sh"
  source "${SCRIPT_DIR}/modules/steps/09_verify.sh"
  source "${SCRIPT_DIR}/modules/steps/10_finalize.sh"

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

  ### MAIN ###
  main() {
    setup_colors
    header "Instalador Arch Linux (UEFI)"
    info "Iniciando instalador de Arch Linux..."
    echo
  
    check_root
    check_uefi
    check_commands
  
    info "Sincronizando reloj del sistema..."
    timedatectl
    success "Reloj sincronizado"
  
    pause

    # Recopilar todas las decisiones primero
    collect_plan

    # Ejecutar instalación completa
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
  # Advertencia importante
