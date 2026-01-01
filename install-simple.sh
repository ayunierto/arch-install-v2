#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Instalación simple y guiada de Arch (modo UEFI) en una sola pasada.
# Usa cfdisk para crear particiones y luego te deja elegirlas por número.
# Advertencia: formatea las particiones seleccionadas.

PKGS=(base linux linux-firmware base-devel neovim networkmanager grub os-prober sudo)

confirm() {
  local prompt="${1:-¿Continuar?}"
  local default="${2:-N}"
  local ans
  read -rp "$prompt [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

header() {
  clear
  echo "======================================"
  echo " Arch Linux – Instalación sencilla"
  echo "======================================"
  echo
}

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

need_cmds() {
  local missing=0
  local cmds=(lsblk cfdisk mkfs.fat mkfs.ext4 mkswap swapon mount pacstrap genfstab)
  for c in "${cmds[@]}"; do
    if ! command -v "$c" &>/dev/null; then
      echo "Falta comando: $c"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || error "Instala los comandos faltantes en el live-ISO."
}

choose_disk() {
  mapfile -t disks < <(lsblk -dpno NAME,TYPE,SIZE,MODEL | awk '$2=="disk" {print $1" "$3" "$4}')
  if (( ${#disks[@]} == 0 )); then
    echo "No se detectaron discos."
    return 1
  fi
  echo "Discos detectados:"
  for i in "${!disks[@]}"; do
    printf "  [%d] %s\n" "$((i + 1))" "${disks[$i]}"
  done
  echo "  [q] Volver"
  read -rp "Elige disco para abrir cfdisk: " choice
  [[ "$choice" == "q" ]] && return 1
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#disks[@]} )); then
    local entry="${disks[$((choice - 1))]}"
    local disk_path="${entry%% *}"
    cfdisk "$disk_path"
  else
    echo "Selección inválida."
  fi
}

select_part() {
  local label="$1"; local required="${2:-0}"; local outvar="$3"
  while true; do
    mapfile -t parts < <(lsblk -rpno NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT | awk '$2=="part" {print $1" "$3" "$4" "$5}')
    if (( ${#parts[@]} == 0 )); then
      echo "No hay particiones. Ejecuta cfdisk primero."
      return 1
    fi
    echo
    echo "Elige $label:" 
    printf "  %-4s %-28s %-10s %-10s %-10s\n" "Idx" "DISPOSITIVO" "TAM" "FSTYPE" "MOUNT"
    printf "  %-4s %-28s %-10s %-10s %-10s\n" "----" "----------------------------" "--------" "--------" "--------"
    for i in "${!parts[@]}"; do
      entry="${parts[$i]}"; p_path="${entry%% *}"; rest="${entry#* }"
      p_size="${rest%% *}"; rest="${rest#* }"
      p_fs="${rest%% *}"; p_mnt="${rest#* }"
      printf "  [%2d] %-28s %-10s %-10s %-10s\n" "$((i + 1))" "$p_path" "$p_size" "${p_fs:--}" "${p_mnt:--}"
    done
    if [[ "$required" -eq 0 ]]; then
      echo "  [0] Omitir $label"
    fi
    echo "  [q] Volver"
    read -rp "Opción: " choice

    [[ "$choice" == "q" ]] && return 1
    if [[ "$choice" == "0" && "$required" -eq 0 ]]; then
      printf -v "$outvar" '%s' ""
      echo "$label: omitido"
      return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#parts[@]} )); then
      entry="${parts[$((choice - 1))]}"; part_path="${entry%% *}"
      echo "Seleccionado: $part_path"
      confirm "¿Confirmar $label = $part_path?" && { printf -v "$outvar" '%s' "$part_path"; return 0; }
    else
      echo "Selección inválida."
    fi
  done
}

### Inicio
header
[[ $EUID -eq 0 ]] || error "Ejecuta como root"
[[ -d /sys/firmware/efi ]] || error "Este flujo asume UEFI; arranca el ISO en modo UEFI"
need_cmds

echo "Este script FORMATEARÁ las particiones que elijas y realizará pacstrap y genfstab."
confirm "¿Continuar?" || exit 1

echo
if confirm "¿Quieres abrir cfdisk para crear/ajustar particiones?" "Y"; then
  choose_disk || true
fi

echo
select_part "EFI (FAT32)" 1 EFI_PART
select_part "SWAP" 0 SWAP_PART
select_part "ROOT (/)" 1 ROOT_PART

[[ -n "${ROOT_PART:-}" ]] || error "Debes seleccionar ROOT"
[[ -n "${EFI_PART:-}" ]] || error "Debes seleccionar EFI"

echo
echo "Resumen:" 
echo "  EFI : ${EFI_PART}"
echo "  SWAP: ${SWAP_PART:-no usado}"
echo "  ROOT: ${ROOT_PART}"
confirm "¿Proceder a formatear y montar?" || exit 1

echo "Formateando..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
if [[ -n "${SWAP_PART:-}" ]]; then
  mkswap "$SWAP_PART"
fi

echo "Montando..."
mount "$ROOT_PART" /mnt
mount --mkdir "$EFI_PART" /mnt/boot
if [[ -n "${SWAP_PART:-}" ]]; then
  swapon "$SWAP_PART"
fi

header
echo "Instalando paquetes base en /mnt..."
pacstrap -K /mnt "${PKGS[@]}"

echo "Generando fstab..."
mkdir -p /mnt/etc
genfstab -U /mnt > /mnt/etc/fstab

echo
echo "Listo. Pasos siguientes dentro del chroot (ejecuta: arch-chroot /mnt):"
cat <<'EOF'
1) Zona horaria: ln -sf /usr/share/zoneinfo/REGION/CIUDAD /etc/localtime && hwclock --systohc
2) Locales: editar /etc/locale.gen (descomenta en_US.UTF-8 y es_ES.UTF-8) y correr locale-gen
3) echo 'LANG=en_US.UTF-8' > /etc/locale.conf
4) echo 'mi-hostname' > /etc/hostname ; ajustar /etc/hosts
5) passwd   (para root)
6) useradd -m -G wheel -s /bin/bash usuario && passwd usuario
   sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
7) systemctl enable NetworkManager
8) Habilitar os-prober en GRUB:
   sed -i 's/^#*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
   grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
   grub-mkconfig -o /boot/grub/grub.cfg
9) exit y reboot
EOF

echo "Cuando termines, desmonta: swapoff -a; umount -R /mnt y reboot."
echo "Fin."
