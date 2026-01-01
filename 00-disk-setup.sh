#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Arch Install Guided - montaje/formatado asistido (no hace pacstrap)
# Revisa y adapta antes de usar. Ejecutar como root en entorno live-ISO Arch.

### ESTADO ###
ROOT_PART=""
EFI_PART=""
HOME_PART=""
SWAP_PART=""

### UTILIDADES ###
pause() { read -rp "Presiona ENTER para continuar..."; }

confirm() {
  local prompt="${1:-¿Continuar?}"
  local default="${2:-N}" # por defecto No
  local ans
  read -rp "$prompt [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

header() {
  clear
  echo "======================================"
  echo " Arch Linux – Disk Setup (Manual-Guiado)"
  echo "======================================"
  echo
}

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

check_commands() {
  local cmds=(lsblk cfdisk mkfs.fat mkfs.ext4 mkswap swapon mount blkid genfstab)
  for c in "${cmds[@]}"; do
    if ! command -v "$c" &>/dev/null; then
      echo "Aviso: comando '$c' no encontrado en PATH. Puede ser necesario instalarlo o usar el live-ISO de Arch."
    fi
  done
}

# selección guiada de disco para cfdisk
choose_disk_for_cfdisk() {
  mapfile -t disks < <(lsblk -dpno NAME,SIZE,MODEL || true)
  if (( ${#disks[@]} == 0 )); then
    echo "No se detectaron discos."
    pause
    return 1
  fi

  echo "Selecciona un disco para abrir cfdisk:"
  for i in "${!disks[@]}"; do
    printf "  [%d] %s\n" "$((i + 1))" "${disks[$i]}"
  done
  echo "  [q] Volver"
  echo
  read -rp "Opción: " choice

  [[ "$choice" == "q" ]] && return 1
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#disks[@]} )); then
    local disk_entry="${disks[$((choice - 1))]}"
    local disk_path="${disk_entry%% *}"
    cfdisk "$disk_path"
  else
    echo "Selección inválida."
    pause
    return 1
  fi
}

# desmonta/stop swap de /mnt si algo falla
cleanup() {
  set +e
  echo "Ejecutando limpieza (desactivando swap y desmontando /mnt si corresponde)..."
  if mountpoint -q /mnt; then
    umount -R /mnt || true
  fi
  if [[ -n "${SWAP_PART:-}" ]]; then
    swapoff "$SWAP_PART" &>/dev/null || true
  else
    swapoff -a &>/dev/null || true
  fi
}
trap cleanup EXIT

### 1. Comprobaciones
header
[[ $EUID -eq 0 ]] || error "Este script debe ejecutarse como root"
[[ -d /sys/firmware/efi ]] || error "PUERTA: UEFI no detectado (se requiere para este script)"
check_commands

### 2. Listar discos (ofrece cfdisk)
while true; do
  header
  echo "Discos y particiones detectados:"
  echo
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo
  echo "+---------------------------------------+"
  echo "| Opciones                              |"
  echo "+---------------------------------------+"
  echo "|  [1] Abrir cfdisk                     |"
  echo "|  [2] Continuar a selección de part.   |"
  echo "|  [q] Salir                            |"
  echo "+---------------------------------------+"
  echo
  read -rp "Selecciona una opción: " opt
  case "$opt" in
    1)
      choose_disk_for_cfdisk || true
      ;;
    2) break ;;
    q) exit 0 ;;
    *) ;;
  esac
done

### 3. Selección de particiones
select_partition() {
  local label="$1"
  local varname="$2"
  local required="${3:-0}"
  while true; do
    header
    echo "Particiones detectadas (solo TYPE=part):"
    mapfile -t parts < <(lsblk -rpno NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT | awk '$2=="part" {print $1" "$3" "$4" "$5}')
    if (( ${#parts[@]} == 0 )); then
      echo "No se detectaron particiones."
      pause
      return 1
    fi

    printf "  %-4s %-28s %-12s %-12s %-10s\n" "Idx" "DISPOSITIVO" "TAM" "FSTYPE" "MOUNT"
    printf "  %-4s %-28s %-12s %-12s %-10s\n" "----" "----------------------------" "--------" "----------" "----------"
    for i in "${!parts[@]}"; do
      entry="${parts[$i]}"
      p_path="${entry%% *}"
      rest="${entry#* }"
      p_size="${rest%% *}"; rest="${rest#* }"
      p_fs="${rest%% *}"; p_mnt="${rest#* }"
      printf "  [%2d] %-28s %-12s %-12s %-10s\n" "$((i + 1))" "$p_path" "$p_size" "${p_fs:--}" "${p_mnt:--}"
    done
    if [[ "$required" -eq 0 ]]; then
      echo "  [0] Omitir $label"
    fi
    echo "  [q] Volver"
    echo
    read -rp "Selecciona $label: " choice

    [[ "$choice" == "q" ]] && return 1
    if [[ "$choice" == "0" && "$required" -eq 0 ]]; then
      printf "%s: omitido\n" "$label"
      printf -v "$varname" '%s' ""
      return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#parts[@]} )); then
      local entry="${parts[$((choice - 1))]}"
      local part_path="${entry%% *}"
      echo
      echo "Información de $part_path:"
      blkid "$part_path" || true
      echo "¿Confirmar $label = $part_path ?"
      if confirm "Confirmas $label = $part_path ?"; then
        printf -v "$varname" '%s' "$part_path"
        return 0
      fi
    else
      echo "Selección inválida."
      pause
    fi
  done
}

select_partition "EFI (FAT32)" EFI_PART 0
select_partition "ROOT (/)" ROOT_PART 1
select_partition "HOME (/home)" HOME_PART 0
select_partition "SWAP" SWAP_PART 0

[[ -n "$ROOT_PART" ]] || error "ROOT es obligatorio. Reinicia y selecciona una partición raíz."

### 4. Resumen
header
echo "Resumen de particiones seleccionadas:"
echo
echo "EFI  : ${EFI_PART:-no definido}"
echo "ROOT : $ROOT_PART"
echo "HOME : ${HOME_PART:-no definido}"
echo "SWAP : ${SWAP_PART:-no definido}"
echo
if ! confirm "¿Es correcto?"; then
  echo "Cancelado por usuario."
  exit 1
fi

### 5. Pre-checks antes de formatear
header
echo "Comprobando que ninguna partición seleccionada esté montada..."
for p in "$ROOT_PART" ${EFI_PART:+$EFI_PART} ${HOME_PART:+$HOME_PART} ${SWAP_PART:+$SWAP_PART}; do
  if mountpoint -q "$p" 2>/dev/null || grep -q "^$p " /proc/mounts 2>/dev/null; then
    error "La partición $p está montada. Desmonta antes de continuar."
  fi
done

echo
echo "AVISO: se procederá a FORMATEAR las particiones seleccionadas."
echo "Se mostrarán tipos actuales (si existen):"
blkid "$ROOT_PART" || true
[[ -n "$EFI_PART" ]] && blkid "$EFI_PART" || true
[[ -n "$HOME_PART" ]] && blkid "$HOME_PART" || true
[[ -n "$SWAP_PART" ]] && blkid "$SWAP_PART" || true
echo
if ! confirm "¿Seguro que deseas continuar con el formateo?"; then
  echo "Operación cancelada."
  exit 1
fi

### 6. Formateo
header
echo "Formateando..."
if [[ -n "$EFI_PART" ]]; then
  echo "Formateando EFI ($EFI_PART) como FAT32..."
  mkfs.fat -F32 -n EFI "$EFI_PART"
fi

echo "Formateando ROOT ($ROOT_PART) como ext4..."
mkfs.ext4 -F "$ROOT_PART"

if [[ -n "$HOME_PART" ]]; then
  echo "Formateando HOME ($HOME_PART) como ext4..."
  mkfs.ext4 -F "$HOME_PART"
fi

if [[ -n "$SWAP_PART" ]]; then
  echo "Creando swap en $SWAP_PART..."
  mkswap "$SWAP_PART"
fi

### 7. Montaje
header
echo "Montando particiones en /mnt ..."
mount "$ROOT_PART" /mnt
if [[ -n "$EFI_PART" ]]; then
  mkdir -p /mnt/boot/efi
  mount "$EFI_PART" /mnt/boot/efi
fi
if [[ -n "$HOME_PART" ]]; then
  mkdir -p /mnt/home
  mount "$HOME_PART" /mnt/home
fi
if [[ -n "$SWAP_PART" ]]; then
  swapon "$SWAP_PART"
fi

header
echo "Particiones montadas correctamente:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
echo
echo "Siguientes pasos recomendados:"
echo "- 1) Instalar el sistema base: pacstrap /mnt base linux linux-firmware"
echo "- 2) Generar fstab: genfstab -U /mnt >> /mnt/etc/fstab"
echo "- 3) Arch-chroot: arch-chroot /mnt"
echo "- 4) Configurar locale, hostname, usuarios y bootloader (systemd-boot o grub)"
echo
echo "Este script NO instala paquetes ni configura el sistema dentro de chroot."
echo
if command -v genfstab &>/dev/null; then
  echo "Puedes generar /mnt/etc/fstab ahora (opcional):"
  if confirm "Generar /mnt/etc/fstab ahora?"; then
    mkdir -p /mnt/etc
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "/mnt/etc/fstab creado."
  fi
fi
echo
echo "Fin. Sal de la sesión si lo deseas o continúa con pacstrap."
exit 0