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
  echo "Opciones:"
  echo "  [1] Abrir cfdisk"
  echo "  [2] Continuar a selección de particiones"
  echo "  [q] Salir"
  echo
  read -rp "Selecciona una opción: " opt
  case "$opt" in
    1)
      read -rp "Disco para cfdisk (ej: /dev/nvme0n1 o /dev/sda): " disk
      [[ -b "$disk" ]] || { echo "Disco no válido"; pause; continue; }
      cfdisk "$disk"
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
  while true; do
    header
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
    echo
    read -rp "Ingresa la partición para $label (ej: /dev/nvme0n1p2) o vacío para omitir: " part
    [[ -z "$part" ]] && { printf "%s: omitido\n" "$label"; return; }
    if [[ -b "$part" ]]; then
      echo
      echo "Información de $part:"
      blkid "$part" || true
      echo "¿Confirmar $label = $part ?"
      if confirm "Confirmas $label = $part ?"; then
        printf -v "$varname" '%s' "$part"
        return
      fi
    else
      echo "Partición no válida: $part"
      pause
    fi
  done
}

select_partition "EFI (FAT32)" EFI_PART
select_partition "ROOT (/)" ROOT_PART
select_partition "HOME (/home)" HOME_PART
select_partition "SWAP" SWAP_PART

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