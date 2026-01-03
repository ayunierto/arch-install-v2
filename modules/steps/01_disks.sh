#!/usr/bin/env bash
# shellcheck shell=bash
# Paso 1: Preparar discos y particiones

choose_disk_for_cfdisk() {
  mapfile -t disks < <(lsblk -dpno NAME,TYPE,SIZE,MODEL | awk '$2=="disk" {print $1" "$3" "$4}')
  if (( ${#disks[@]} == 0 )); then
    warn "No se detectaron discos"
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
    warn "Selección inválida"
    pause
    return 1
  fi
}

select_partition() {
  local label="$1"
  local varname="$2"
  local required="${3:-0}"
  
  while true; do
    header "Instalación Arch Linux (UEFI)"
    step_banner "1" "Selección de partición: $label"
    
    mapfile -t parts < <(lsblk -rpno NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT | awk '$2=="part" {print $1" "$3" "$4" "$5}')
    if (( ${#parts[@]} == 0 )); then
      warn "No se detectaron particiones. Crea particiones primero con cfdisk"
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
      warn "Selección inválida"
      pause
    fi
  done
}

step_prepare_disks() {
  header "Instalación Arch Linux (UEFI)"
  step_banner "1" "Aplicando particiones y montaje"

  [[ -n "$ROOT_PART" ]] || error "ROOT es obligatorio"
  [[ -n "$EFI_PART" ]] || error "EFI es obligatorio"

  info "Estado actual de discos antes de aplicar"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  line

  # Verificar que no estén montadas
  for p in "$ROOT_PART" "$EFI_PART" ${HOME_PART:+"$HOME_PART"} ${SWAP_PART:+"$SWAP_PART"}; do
    if mountpoint -q "$p" 2>/dev/null || grep -q "^$p " /proc/mounts 2>/dev/null; then
      error "La partición $p está montada. Desmonta antes de continuar"
    fi
  done

  section "Formateando y montando"

  # EFI
  if [[ "${FORMAT_EFI:-no}" == "yes" ]]; then
    info "Formateando EFI ($EFI_PART) como FAT32..."
    mkfs.fat -F32 "$EFI_PART"
    success "EFI formateado"
  else
    info "Usando EFI existente ($EFI_PART) sin formatear"
    if ! blkid "$EFI_PART" | grep -q "TYPE=\"vfat\""; then
      error "La partición EFI no es FAT32. Formatea o corrige antes de continuar"
    fi
  fi

  # ROOT (siempre formatear)
  info "Formateando ROOT ($ROOT_PART) como ext4..."
  mkfs.ext4 -F "$ROOT_PART"
  success "ROOT formateado"

  # HOME
  if [[ -n "$HOME_PART" ]]; then
    if [[ "${FORMAT_HOME:-yes}" == "yes" ]]; then
      info "Formateando HOME ($HOME_PART) como ext4..."
      mkfs.ext4 -F "$HOME_PART"
      success "HOME formateado"
    else
      info "Usando HOME existente ($HOME_PART) sin formatear"
    fi
  fi

  # SWAP
  if [[ -n "$SWAP_PART" && "${ENABLE_SWAP:-yes}" == "yes" ]]; then
    info "Creando SWAP en $SWAP_PART..."
    mkswap "$SWAP_PART"
    success "SWAP creado"
  fi

  # Montar
  mount "$ROOT_PART" /mnt
  success "ROOT montado en /mnt"

  mount --mkdir "$EFI_PART" /mnt/boot
  success "EFI montado en /mnt/boot"

  if ! mountpoint -q /mnt/boot; then
    error "CRÍTICO: /mnt/boot no está montado correctamente"
  fi
  if ! touch /mnt/boot/.test 2>/dev/null; then
    error "CRÍTICO: No se puede escribir en /mnt/boot"
  fi
  rm -f /mnt/boot/.test

  if [[ -n "$HOME_PART" ]]; then
    mount --mkdir "$HOME_PART" /mnt/home
    success "HOME montado en /mnt/home"
  fi

  if [[ -n "$SWAP_PART" && "${ENABLE_SWAP:-yes}" == "yes" ]]; then
    swapon "$SWAP_PART"
    success "SWAP activado"
  fi

  echo
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
  pause
}
